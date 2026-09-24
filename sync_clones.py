"""Launch three WeChats, updating stopped clones transactionally from the main app."""
import fcntl
import os
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

from prepare_clone import MAIN_ID, configure, run

LS = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'


def info(app):
    return plistlib.loads((app / 'Contents/Info.plist').read_bytes())


def version(app):
    data = info(app)
    result = []
    for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
        value = str(data[key])
        if not re.fullmatch(r'\d+(?:\.\d+)*', value):
            raise ValueError(f'无法安全比较版本：{value}')
        parts = list(map(int, value.split('.')))
        while len(parts) > 1 and parts[-1] == 0:
            parts.pop()
        result.append(tuple(parts))
    return tuple(result)


class Mac:
    def processes(self, app):
        prefix = str(app) + '/Contents/'
        rows = run('/bin/ps', '-axo', 'pid=,comm=').stdout.decode().splitlines()
        return [int(row.split(None, 1)[0]) for row in rows
                if len(row.split(None, 1)) == 2 and row.split(None, 1)[1].startswith(prefix)]

    def launch(self, app):
        run('/usr/bin/open', app)

    def prepare(self, main, staged, number):
        run('/usr/bin/codesign', '--verify', '--deep', '--strict', main)
        run('/usr/bin/ditto', main, staged)
        configure(main, staged, number)

    def register(self, app):
        run(LS, '-f', app)

    def healthy(self, app):
        probe = Path(__file__).with_name('clone_health')
        deadline = time.monotonic() + 60
        stable = None
        while time.monotonic() < deadline:
            ready = subprocess.run([str(probe), str(app)], capture_output=True).returncode == 0
            if ready:
                stable = stable or time.monotonic()
                if time.monotonic() - stable >= 10:
                    return True
            else:
                stable = None
            time.sleep(1)
        return False

    def stop_candidate(self, app):
        # Only called for the candidate launched by this transaction.
        for pid in self.processes(app):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + 10
        while self.processes(app) and time.monotonic() < deadline:
            time.sleep(.5)
        if self.processes(app):
            raise RuntimeError('新版分身尚未退出，已保留旧程序；退出分身后重开启动器恢复。')


def sync_one(main, app, number, work, backend):
    work.mkdir(parents=True, exist_ok=True)
    backup, staged, failed = [work / name for name in ('previous.app', 'staged.app', 'failed.app')]
    # A backup left by interruption is never silently discarded.
    if backup.exists():
        if backend.processes(app):
            return f'微信{number}上次升级未完成；请退出该分身后重开启动器恢复旧版。'
        if failed.exists():
            shutil.rmtree(failed)
        if app.exists():
            app.rename(failed)
        backup.rename(app)
        backend.register(app)
        backend.launch(app)
        return f'微信{number}已恢复上次升级前的版本，本次暂不再次升级。'
    if app.exists() and info(app)['CFBundleIdentifier'] != f'{MAIN_ID}.clone{number}':
        raise ValueError(f'微信{number}应用身份不匹配，拒绝覆盖。')
    target = version(main)
    if app.exists() and version(app) >= target:
        backend.launch(app)
        return None
    if backend.processes(app):
        return f'微信{number}正在运行，已延后更新；退出它后再打开启动器。'
    if staged.exists():
        shutil.rmtree(staged)
    try:
        backend.prepare(main, staged, number)
        if version(main) != target or version(staged) != target:
            raise RuntimeError('主微信在准备过程中版本发生变化，请重新启动。')
        if backend.processes(app):
            return f'微信{number}已启动，本次延后更新。'
        if app.exists():
            app.rename(backup)
        try:
            staged.rename(app)
            backend.register(app)
            backend.launch(app)
            if not backend.healthy(app):
                raise RuntimeError('新版未能持续显示正常应用窗口。')
        except Exception:
            backend.stop_candidate(app)
            if failed.exists():
                shutil.rmtree(failed)
            if app.exists():
                app.rename(failed)
            if backup.exists():
                backup.rename(app)
                backend.register(app)
                backend.launch(app)
            raise
        if backup.exists():
            shutil.rmtree(backup)
        if failed.exists():
            shutil.rmtree(failed)
        return None
    except Exception as error:
        # Preparation failure leaves the old application in place.
        if app.exists() and not backup.exists() and not backend.processes(app):
            backend.launch(app)
        detail = error.stderr.decode(errors='replace') if isinstance(error, subprocess.CalledProcessError) else str(error)
        return f'微信{number}更新失败：{detail}\n旧程序如存在已保留；未修改聊天数据。'


def main():
    main_app = Path('/Applications/WeChat.app')
    state = Path('/Applications/.wechat-clone-update')
    state.mkdir(exist_ok=True)
    with (state / 'update.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('另一个启动器正在检查或更新，请稍候。')
            return 0
        backend = Mac()
        if info(main_app)['CFBundleIdentifier'] != MAIN_ID:
            raise ValueError('主微信应用身份不匹配。')
        backend.launch(main_app)
        messages = []
        for number in (2, 3):
            try:
                message = sync_one(main_app, Path(f'/Applications/WeChat {number}.app'),
                                   number, state / f'clone{number}', backend)
                if message:
                    messages.append(message)
            except Exception as error:
                messages.append(f'微信{number}：{error}')
        if messages:
            print('\n'.join(messages), file=sys.stderr)
            return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        sys.exit(str(error))
