#!/usr/bin/env python3
"""Create an isolated CI simulator rather than relying on runner device names."""
import json
import os
import subprocess


def select_runtime(runtimes):
    candidates=[]
    for runtime in runtimes:
        try:
            version=tuple(int(n) for n in runtime['version'].split('.'))
        except (KeyError, ValueError, TypeError):
            continue
        if runtime.get('isAvailable') is True and '.iOS-' in runtime.get('identifier', '') and version >= (26,):
            candidates.append((version,runtime['identifier']))
    return max(candidates)[1] if candidates else None


def run(*args):
    return subprocess.check_output(args,text=True).strip()


def main():
    def runtime():
        return select_runtime(json.loads(run('xcrun','simctl','list','runtimes','--json'))['runtimes'])
    selected=runtime()
    if selected is None:
        subprocess.run(['xcodebuild','-downloadPlatform','iOS'],check=True)
        selected=runtime()
    if selected is None:
        raise SystemExit('No available iOS 26+ simulator runtime after platform download.')
    types=json.loads(run('xcrun','simctl','list','devicetypes','--json'))['devicetypes']
    preferred=['com.apple.CoreSimulator.SimDeviceType.iPhone-17','com.apple.CoreSimulator.SimDeviceType.iPhone-16']
    kind=next((item for item in preferred if any(t['identifier']==item for t in types)),None)
    if not kind:
        raise SystemExit('No supported iPhone simulator device type.')
    device=run('xcrun','simctl','create','ABM-CI-'+os.environ.get('GITHUB_RUN_ID','local'),kind,selected)
    # Fresh runners can attach a virtual hardware keyboard. Our UI test must
    # exercise the software keyboard and its Done toolbar, not bypass them.
    subprocess.run(['defaults','write','com.apple.iphonesimulator','ConnectHardwareKeyboard','-bool','false'],check=True)
    subprocess.run(['xcrun','simctl','boot',device],check=True)
    subprocess.run(['xcrun','simctl','bootstatus',device,'-b'],check=True)
    with open(os.environ['GITHUB_ENV'],'a') as env:
        env.write('ABM_SIMULATOR_ID='+device+'\n')
    print('Prepared isolated simulator:',device,'runtime:',selected)


if __name__=='__main__':
    main()
