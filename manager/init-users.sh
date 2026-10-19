#!/usr/bin/env bash
# Create workshop projects/users and export their credentials to Excel.
set -euo pipefail
umask 077
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
export WORKSHOP_MANAGER_DIR="$TASK_ROOT"
exec python3 - "$@" <<'WORKSHOP_PYTHON'
#!/usr/bin/env python3
# coding: utf-8
"""Provision workshop identities. No third-party Python dependency is required."""
import argparse, datetime, json, os, re, secrets, shutil, string, subprocess, sys, tempfile, zipfile
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(os.environ['WORKSHOP_MANAGER_DIR'])
POLICY = {"length":24,"uppercase":2,"lowercase":2,"digit":2,"special_char":2}

def atomic(path, content):
    path = Path(path)
    fd, tmp = tempfile.mkstemp(prefix='.'+path.name, dir=path.parent)
    try:
        with os.fdopen(fd,'w',encoding='utf-8') as f:
            f.write(content); f.flush(); os.fsync(f.fileno())
        os.chmod(tmp,0o600); os.replace(tmp,path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def password(policy):
    groups = [(string.ascii_uppercase,'uppercase'),(string.ascii_lowercase,'lowercase'),(string.digits,'digit'),('!@#$%^&*_-+=?','special_char')]
    result = [secrets.choice(chars) for chars,key in groups for _ in range(policy[key])]
    alphabet = ''.join(chars for chars,_ in groups)
    result += [secrets.choice(alphabet) for _ in range(max(policy['length'],len(result))-len(result))]
    secrets.SystemRandom().shuffle(result)
    return ''.join(result)

def xlsx(path, rows, url):
    headers=['Project','User','Password','Email','Role','Status','Platform URL','Updated at (UTC)']
    records=[headers]+[[r['project'],r['user'],r['password'],r['email'],'Project Admin',r['status'],url,r.get('updated','')] for r in rows]
    xmlrows=[]
    for n,row in enumerate(records,1):
        cells=[]
        for i,val in enumerate(row):
            ref=chr(65+i)+str(n); value=escape(str(val))
            cells.append(f'<c r="{ref}" s="{1 if n==1 else 2 if n%2==0 else 0}" t="inlineStr"><is><t xml:space="preserve">{value}</t></is></c>')
        xmlrows.append(f'<row r="{n}" ht="26" customHeight="1">'+''.join(cells)+'</row>')
    sheet='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:H'+str(len(records))+'"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>'+''.join(f'<col min="{i}" max="{i}" width="{w}" customWidth="1"/>' for i,w in enumerate([18,18,40,34,22,26,42,26],1))+'</cols><sheetData>'+''.join(xmlrows)+'</sheetData><autoFilter ref="A1:H'+str(len(records))+'"/></worksheet>'
    parts={
      '[Content_Types].xml':'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
      '_rels/.rels':'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
      'xl/workbook.xml':'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Workshop users" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels':'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
      'xl/styles.xml':'<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF185C37"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF0F5F1"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="3"><xf fontId="0" fillId="0" borderId="0" xfId="0"/><xf fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/><xf fontId="0" fillId="3" borderId="0" xfId="0" applyFill="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>',
      'xl/worksheets/sheet1.xml':sheet}
    fd,tmp=tempfile.mkstemp(prefix='.'+path.name,dir=path.parent);os.close(fd)
    try:
        with zipfile.ZipFile(tmp,'w',zipfile.ZIP_DEFLATED) as z:
            for k,v in parts.items():z.writestr(k,v)
        os.chmod(tmp,0o600);os.replace(tmp,path)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)

def main():
    p=argparse.ArgumentParser(description='Create projectN / userN; use --apply to perform provisioning. Existing names are never adopted or reset.')
    p.add_argument('--server-id',required=True,help='Configured platform-admin CLI Server ID')
    p.add_argument('--platform-url',required=True,help='Must match that CLI server, HTTPS, without /artifactory')
    p.add_argument('--email-domain',required=True,help='Domain or controlled mail sink for userN@domain')
    p.add_argument('--count',type=int,default=10);p.add_argument('--start',type=int,default=1)
    p.add_argument('--password-policy',type=Path,help='JSON containing length, uppercase, lowercase, digit, special_char minima; merged with strong defaults')
    p.add_argument('--output',type=Path,default=ROOT/'workshop_users.xlsx')
    p.add_argument('--apply',action='store_true');p.add_argument('--resume',action='store_true')
    p.add_argument('--check',action='store_true',help='Read-only platform name-collision check; creates no resources or output files')
    a=p.parse_args()
    if a.check and (a.apply or a.resume):p.error('--check cannot be combined with --apply or --resume')
    if a.count<1 or a.count>500 or a.start<1:p.error('count must be 1..500 and start >= 1')
    url=a.platform_url.rstrip('/')
    if not re.fullmatch(r'https://[^/?#@]+(?::[0-9]+)?',url):p.error('Use a platform root HTTPS URL, without credentials or service path')
    if not re.fullmatch(r'[A-Za-z0-9.-]+\.[A-Za-z]{2,}',a.email_domain):p.error('Invalid email domain')
    policy=POLICY.copy()
    if a.password_policy:
        extra=json.loads(a.password_policy.read_text())
        if set(extra)-set(policy):p.error('Unknown password policy field')
        for key,value in extra.items():
            if type(value)!=int or not 0<=value<=128:p.error('Invalid policy minimum')
            policy[key]=max(policy[key],value)
    policy['length']=max(policy['length'],sum(policy[k] for k in policy if k!='length'))
    if policy['length']>128:p.error('Requested password exceeds 128 chars; check tenant constraints')
    if not a.apply and not a.check:
        print(f'PLAN ONLY: {a.count} identities on {url}, CLI Server ID={a.server_id}')
        for i in range(a.start,a.start+a.count):print(f'project{i} -> user{i} -> Project Admin')
        print('No API called, no password generated, no XLSX overwritten. Add --apply to execute.');return
    if not shutil.which('jf') or not shutil.which('jq'):p.error('Instructor needs jf >=2.100.0 and jq on PATH')
    env=os.environ.copy();env['JFROG_CLI_LOG_LEVEL']='INFO';env.setdefault('JFROG_CLI_USER_AGENT','jfrog-workshop-provision/1.0');env['JFROG_CLI_OFFER_CONFIG']='false'
    # jfcm's non-interactive shim otherwise merges stderr into stdout and
    # records response bodies in its command history. Its documented switch
    # preserves the actual CLI streams for this process only.
    env['jfcm_NO_HISTORY']='1'
    def cli(arguments,payload=None):
        result=subprocess.run(['jf']+arguments,input=payload,capture_output=True,text=True,env=env)
        body_lines=[];log_lines=[]
        for line in result.stdout.splitlines():
            clean=re.sub(r'\x1b\[[0-9;]*m','',line)
            if re.match(r'^\s*(?:\d{2}:\d{2}:\d{2}\s+)?\[(?:Info|Warn|Error|Debug)\]\s',clean,re.IGNORECASE):log_lines.append(clean)
            else:body_lines.append(line)
        result.stdout='\n'.join(body_lines)
        result.stderr=re.sub(r'\x1b\[[0-9;]*m','',result.stderr)+'\n'+'\n'.join(log_lines)
        return result
    version=cli(['--version']).stdout
    m=re.search(r'(\d+)\.(\d+)\.(\d+)',version)
    if not m or tuple(map(int,m.groups()))<(2,100,0):p.error('jf api needs JFrog CLI >=2.100.0')
    # Export one named config only; compare target without displaying credentials.
    result=cli(['config','export',a.server_id])
    import base64
    try:
        raw=result.stdout.strip();cfg=json.loads(base64.b64decode(raw))
        if isinstance(cfg,list):cfg=cfg[0]
        configured=(cfg.get('url') or cfg.get('artifactoryUrl','').removesuffix('/artifactory')).rstrip('/')
        if configured!=url:raise ValueError('URL mismatch')
    except Exception:raise RuntimeError('Cannot verify CLI Server ID / URL. Check jf config export support and that the URL matches; no API called.')
    finally:cfg=None;result=None
    def api(method,path,body=None,missing=False):
        # Some CLI builds stop parsing options at the first positional argument.
        # Put all options before the endpoint for compatibility with both parsers.
        cmd=['api','--server-id',a.server_id,'--timeout','30','-X',method]
        if body is not None:cmd+=['-H','Content-Type: application/json','--input','-']
        cmd.append(path)
        r=cli(cmd,json.dumps(body) if body is not None else None)
        # jf api logs HTTP status at INFO/WARN. ERROR hides both, even for a
        # normal existence-probe 404. Capture those logs, but never print bodies.
        statuses=re.findall(r'(?:Http Status:|returned|HTTP/\d(?:\.\d)?)\s*([1-5]\d{2})\b',r.stderr,re.IGNORECASE)
        if not statuses:statuses=re.findall(r'^\s*([1-5]\d{2})\s*$',r.stderr,re.MULTILINE)
        status=int(statuses[-1]) if statuses else None
        if r.returncode or (status is not None and status>=400):
            if missing and status==404:return None
            hints={400:'Request rejected; check tenant validation rules.',401:'Authentication failed; refresh this Server ID credential.',403:'Permission denied; this operation requires platform administrator privileges.',404:'API or resource not found.',409:'A resource with the same name already exists.',429:'Platform rate limit reached; retry later.'}
            hint=hints.get(status,'Check this Server ID, CLI output, network and platform logs.')
            if status is None:
                # Only CLI/transport log text; never echo a response body.
                detail=re.sub(r'\x1b\[[0-9;]*m','',r.stderr).strip()
                detail=re.sub(r'(?i)(Bearer\s+)[A-Za-z0-9._~+/-]+',r'\1[redacted]',detail)
                detail=re.sub(r'eyJ[A-Za-z0-9._-]+','[redacted JWT]',detail)
                if body:
                    for key,value in body.items():
                        if key in ('password','access_token','token') and isinstance(value,str):detail=detail.replace(value,'[redacted]')
                if detail:hint+=' CLI: '+detail[-500:]
            raise RuntimeError(f'{method} {path} failed: HTTP {status if status is not None else "unknown"} (CLI exit {r.returncode}). {hint}')
        if not r.stdout.strip():return {}
        j=subprocess.run(['jq','-c','.'],input=r.stdout,capture_output=True,text=True)
        if j.returncode:raise RuntimeError(f'Non-JSON response: {method} {path}')
        return json.loads(j.stdout)
    output=a.output.resolve();output.parent.mkdir(parents=True,exist_ok=True)
    statefile=output.with_suffix('.state.json')
    # A portable exclusive lock prevents concurrent password journals / provisioning.
    lock=output.with_suffix('.lock')
    try:lock.mkdir(mode=0o700)
    except FileExistsError:raise RuntimeError(f'Provisioning lock exists: {lock}. Verify that no run is active before removing a stale lock.')
    import atexit
    atexit.register(lambda: lock.rmdir() if lock.exists() else None)
    if a.resume:
        if not statefile.exists():p.error('No matching recovery state; cannot resume or reset existing users')
        state=json.loads(statefile.read_text())
        if state['server_id']!=a.server_id or state['url']!=url or state['start']!=a.start or state['count']!=a.count or state['email_domain']!=a.email_domain:p.error('Resume arguments differ from recovery state')
        rows=state['rows']
    else:
        if statefile.exists():p.error('A recovery record already exists. Add --resume with the original arguments; existing passwords will be preserved.')
        # Full name-collision preflight before any mutations.
        for i in range(a.start,a.start+a.count):
            print(f'CHECK {i-a.start+1}/{a.count}: project{i} / user{i}',flush=True)
            if api('GET',f'/access/api/v1/projects/project{i}',missing=True) is not None or api('GET',f'/access/api/v2/users/user{i}',missing=True) is not None:raise RuntimeError(f'project{i} or user{i} already exists. No existing account will be modified; use another --start.')
        if a.check:
            print(f'CHECK PASSED: {a.count} project/user pairs are available on {url}. No platform resources, passwords or Excel files created.')
            return
        if output.exists():
            stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
            backup=output.with_name(output.stem+'.backup-'+stamp+'-'+secrets.token_hex(3)+output.suffix)
            output.rename(backup)
            print(f'Existing Excel preserved as: {backup.name}')
        rows=[dict(project=f'project{i}',user=f'user{i}',email=f'user{i}@{a.email_domain}',password=password(policy),status='PENDING',project_created=False,user_created=False,member_assigned=False) for i in range(a.start,a.start+a.count)]
        state=dict(server_id=a.server_id,url=url,start=a.start,count=a.count,email_domain=a.email_domain,rows=rows)
    def save():
        atomic(statefile,json.dumps(state,ensure_ascii=False,indent=2))
        xlsx(output,rows,url)
    save() # durable password journal before the first create request
    for row in rows:
        try:
            if row['status']=='READY':continue
            if row['status'].startswith('IN_FLIGHT'):
                raise RuntimeError('Previous request may have reached the server. Inspect the tenant and this recovery record before resuming; no automatic retry/reset.')
            if not row['project_created']:
                row['status']='IN_FLIGHT_PROJECT';save()
                api('POST','/access/api/v1/projects',dict(project_key=row['project'],display_name=row['project'],description='JFrog AI Catalog onsite workshop',admin_privileges=dict(manage_members=True,manage_resources=True,index_resources=True)))
                row['project_created']=True;row['status']='PROJECT_CREATED';save()
            if not row['user_created']:
                row['status']='IN_FLIGHT_USER';save()
                api('POST','/access/api/v2/users',dict(username=row['user'],email=row['email'],password=row['password'],admin=False,profile_updatable=True,internal_password_disabled=False,disable_ui_access=False,groups=[]))
                row['user_created']=True;row['status']='USER_CREATED';save()
            roles=api('GET',f"/access/api/v1/projects/{row['project']}/roles")
            if isinstance(roles,dict):roles=roles.get('roles',[])
            if not any(r.get('name')=='Project Admin' for r in roles):raise RuntimeError('Exact Project Admin role not present; stopped without guessing a role')
            row['status']='IN_FLIGHT_MEMBERSHIP';save()
            api('PUT',f"/access/api/v1/projects/{row['project']}/users/{row['user']}",dict(roles=['Project Admin']))
            actual=api('GET',f"/access/api/v1/projects/{row['project']}/users/{row['user']}")
            user=api('GET',f"/access/api/v2/users/{row['user']}")
            if 'Project Admin' not in actual.get('roles',[]) or user.get('admin') is not False:raise RuntimeError('Membership / platform-admin verification failed')
            row['member_assigned']=True;row['status']='READY';row['updated']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
            print(f"READY {row['project']} / {row['user']} / Project Admin")
        except Exception:
            save();raise
    print(f'Created and verified {len(rows)} identities. XLSX: {output}')
    print('Contains plaintext passwords. Keep instructor-only; distribute only the individual attendee row. Recovery state also contains passwords.')

if __name__=='__main__':
    try:main()
    except (Exception,KeyboardInterrupt) as e:
        print('STOP: '+(str(e) or 'Interrupted; check recovery state before retrying'),file=sys.stderr);sys.exit(1)

WORKSHOP_PYTHON
