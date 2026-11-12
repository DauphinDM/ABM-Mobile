import importlib.util
import pathlib
import unittest

spec=importlib.util.spec_from_file_location('simulator',pathlib.Path(__file__).resolve().parents[1]/'bin/prepare-ios-simulator.py')
simulator=importlib.util.module_from_spec(spec)
spec.loader.exec_module(simulator)


class RuntimeTests(unittest.TestCase):
    def runtime(self,version,available=True,platform='iOS'):
        return dict(version=version,isAvailable=available,identifier='com.apple.CoreSimulator.SimRuntime.'+platform+'-'+version.replace('.','-'))

    def test_missing_requires_platform_download(self):
        self.assertIsNone(simulator.select_runtime([]))

    def test_only_available_ios_26_or_later(self):
        self.assertIsNone(simulator.select_runtime([self.runtime('25.9'),self.runtime('27.0',False),self.runtime('30.0',platform='tvOS')]))

    def test_numeric_version_order(self):
        selected=simulator.select_runtime([self.runtime('26.9'),self.runtime('26.10'),self.runtime('26.4')])
        self.assertTrue(selected.endswith('iOS-26-10'))

    def test_malformed_entries_do_not_hide_a_usable_runtime(self):
        selected=simulator.select_runtime([{},dict(version='invalid'),self.runtime('26.5')])
        self.assertTrue(selected.endswith('iOS-26-5'))


if __name__=='__main__':
    unittest.main()
