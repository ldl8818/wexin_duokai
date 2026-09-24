"""Shared clone configuration for manual and launch-time upgrades."""
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

MAIN_ID = 'com.tencent.xinWeChat'
ROOT = Path(__file__).resolve().parent


def run(*args):
    return subprocess.run([str(arg) for arg in args], check=True, capture_output=True)


def configure(main, app, number):
    if number < 2 or app.resolve() == main.resolve():
        raise ValueError('拒绝修改非分身应用。')
    info = app / 'Contents/Info.plist'
    data = plistlib.loads(info.read_bytes())
    bundle_id = f'{MAIN_ID}.clone{number}'
    data.update(CFBundleIdentifier=bundle_id, CFBundleName=f'WeChat {number}',
                CFBundleDisplayName=f'WeChat {number}')
    info.write_bytes(plistlib.dumps(data))
    for language in ('zh-Hans', 'zh-Hant', 'en'):
        strings = app / f'Contents/Resources/{language}.lproj/InfoPlist.strings'
        if strings.exists():
            name = f'WeChat {number}' if language == 'en' else f'微信 {number}'
            for key in ('CFBundleName', 'CFBundleDisplayName'):
                run('/usr/libexec/PlistBuddy', '-c', f'Set :{key} {name}', strings)
    run('/bin/bash', ROOT / 'configure_clone_updates.sh', app)
    entitlements = plistlib.loads(run('/usr/bin/codesign', '-d', '--entitlements', ':-', main).stdout)
    if entitlements.get('com.apple.security.app-sandbox') is not True:
        raise ValueError('主微信缺少沙盒权限，停止升级。')
    for key in ('com.apple.application-identifier', 'com.apple.security.application-groups'):
        value = entitlements.get(key)
        if isinstance(value, str):
            entitlements[key] = value.replace(MAIN_ID, bundle_id)
        elif isinstance(value, list):
            entitlements[key] = [item.replace(MAIN_ID, bundle_id) for item in value]
    with tempfile.TemporaryDirectory(prefix='wechat-sign-') as directory:
        path = Path(directory) / 'entitlements.plist'
        path.write_bytes(plistlib.dumps(entitlements))
        # Never propagate the main app's sandbox entitlements into nested helpers.
        run('/usr/bin/codesign', '--force', '--deep', '--sign', '-', app)
        run('/usr/bin/codesign', '--force', '--sign', '-', '--entitlements', path, app)
        run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)


if __name__ == '__main__':
    try:
        configure(Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]))
    except subprocess.CalledProcessError as error:
        sys.exit(error.stderr.decode(errors='replace'))
