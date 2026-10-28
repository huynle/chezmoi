#!/usr/bin/env python3
import yaml,pathlib,re
w=yaml.safe_load(pathlib.Path('.github/workflows/huynle-release.yml').read_text()); j=w['jobs']
assert j['build']['permissions']=={'contents':'read'}
assert j['macos-sign']['environment']=='fleet-code-signing' and j['macos-sign']['runs-on'].startswith('macos')
assert j['windows-sign']['environment']=='fleet-code-signing' and j['windows-sign']['permissions']=={'contents':'read','id-token':'write'}
mac='\n'.join(str(x.get('run','')) for x in j['macos-sign']['steps']); assert 'hdiutil create' in mac and 'stapler staple "$dmg"' in mac and 'TeamIdentifier' in mac and not re.search(r'stapler staple "?\$f',mac)
u=[x.get('uses','') for x in j['windows-sign']['steps']]; assert 'azure/artifact-signing-action@c7ab2a863ab5f9a846ddb8265964877ef296ee82' in u
win='\n'.join(str(x.get('run','')) for x in j['windows-sign']['steps']); assert 'Get-AuthenticodeSignature' in win and 'signtool verify /pa /all /v' in win
assert j['sign']['environment']=='fleet-release' and set(j['sign']['needs'])=={'build','macos-sign','windows-sign'}
final='\n'.join(str(x.get('run','')) for x in j['sign']['steps']); assert 'merge-native' in final and final.index('merge-native') < final.index('sign-package')
