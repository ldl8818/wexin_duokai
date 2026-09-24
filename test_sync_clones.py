import plistlib
import shutil
import tempfile
import unittest
from pathlib import Path

from sync_clones import MAIN_ID, sync_one, version


def make_app(path, number=None, release='4.1.15', build='270100'):
    (path / 'Contents').mkdir(parents=True)
    data = dict(CFBundleIdentifier=MAIN_ID if number is None else f'{MAIN_ID}.clone{number}',
                CFBundleShortVersionString=release, CFBundleVersion=build)
    (path / 'Contents/Info.plist').write_bytes(plistlib.dumps(data))


class FakeMac:
    def __init__(self):
        self.running = False
        self.prepared = 0
        self.launched = []
        self.ready = True
        self.fail_prepare = False
        self.fail_stop = False
        self.change_source = False

    def processes(self, app):
        return [123] if self.running else []

    def launch(self, app):
        self.launched.append(version(app))
        self.running = True

    def prepare(self, main, staged, number):
        self.prepared += 1
        if self.fail_prepare:
            raise RuntimeError('签名失败')
        shutil.copytree(main, staged)
        path = staged / 'Contents/Info.plist'
        data = plistlib.loads(path.read_bytes())
        data['CFBundleIdentifier'] = f'{MAIN_ID}.clone{number}'
        path.write_bytes(plistlib.dumps(data))
        if self.change_source:
            data['CFBundleVersion'] = '270102'
            (main / 'Contents/Info.plist').write_bytes(plistlib.dumps(data))

    def register(self, app):
        pass

    def healthy(self, app):
        return self.ready

    def stop_candidate(self, app):
        if self.fail_stop:
            raise RuntimeError('新版未退出')
        self.running = False


class SyncTests(unittest.TestCase):
    def setUp(self):
        root = Path(__file__).parent / '.tmp'
        root.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=root, prefix='sync-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.main = self.root / 'WeChat.app'
        self.app = self.root / 'WeChat 2.app'
        self.work = self.root / 'work'
        make_app(self.main)
        self.backend = FakeMac()

    def sync(self):
        return sync_one(self.main, self.app, 2, self.work, self.backend)

    def old_app(self):
        make_app(self.app, 2, build='270099')

    def test_same_version_skips_build(self):
        make_app(self.app, 2)
        self.assertIsNone(self.sync())
        self.assertEqual(self.backend.prepared, 0)
        self.assertEqual(len(self.backend.launched), 1)

    def test_newer_clone_is_not_downgraded(self):
        make_app(self.app, 2, release='4.1.16')
        self.assertIsNone(self.sync())
        self.assertEqual(self.backend.prepared, 0)

    def test_build_number_update_and_backup_cleanup(self):
        self.old_app()
        self.assertIsNone(self.sync())
        self.assertEqual(version(self.app), version(self.main))
        self.assertEqual(self.backend.prepared, 1)
        self.assertFalse((self.work / 'previous.app').exists())

    def test_running_old_clone_is_untouched(self):
        self.old_app()
        before = (self.app / 'Contents/Info.plist').read_bytes()
        self.backend.running = True
        self.assertIn('延后', self.sync())
        self.assertEqual(self.backend.prepared, 0)
        self.assertEqual((self.app / 'Contents/Info.plist').read_bytes(), before)

    def test_prepare_failure_keeps_and_launches_old_app(self):
        self.old_app()
        before = version(self.app)
        self.backend.fail_prepare = True
        self.assertIn('签名失败', self.sync())
        self.assertEqual(version(self.app), before)
        self.assertEqual(self.backend.launched, [before])

    def test_startup_failure_rolls_back_old_app(self):
        self.old_app()
        before = version(self.app)
        self.backend.ready = False
        self.assertIn('更新失败', self.sync())
        self.assertEqual(version(self.app), before)
        self.assertEqual(self.backend.launched, [version(self.main), before])
        self.assertFalse((self.work / 'previous.app').exists())
        self.assertTrue((self.work / 'failed.app').exists())

    def test_stop_failure_keeps_backup_for_next_launch(self):
        self.old_app()
        self.backend.ready = False
        self.backend.fail_stop = True
        self.assertIn('新版未退出', self.sync())
        self.assertTrue((self.work / 'previous.app').exists())
        self.assertIn('上次升级未完成', self.sync())
        self.backend.running = False
        self.assertIn('已恢复', self.sync())
        self.assertEqual(version(self.app)[1], (270099,))

    def test_interrupted_swap_restores_missing_app(self):
        self.work.mkdir()
        make_app(self.work / 'previous.app', 2, build='270099')
        self.assertIn('已恢复', self.sync())
        self.assertTrue(self.app.exists())
        self.assertEqual(self.backend.prepared, 0)

    def test_missing_clone_can_be_created(self):
        self.assertIsNone(self.sync())
        self.assertEqual(version(self.app), version(self.main))

    def test_source_changes_during_prepare_aborts(self):
        self.old_app()
        before = version(self.app)
        self.backend.change_source = True
        self.assertIn('版本发生变化', self.sync())
        self.assertEqual(version(self.app), before)

    def test_wrong_identity_is_rejected(self):
        make_app(self.app)
        with self.assertRaisesRegex(ValueError, '身份不匹配'):
            self.sync()
        self.assertEqual(self.backend.prepared, 0)

    def test_numeric_version_comparison(self):
        make_app(self.app, 2, release='4.1.9')
        self.assertLess(version(self.app), version(self.main))


if __name__ == '__main__':
    unittest.main()
