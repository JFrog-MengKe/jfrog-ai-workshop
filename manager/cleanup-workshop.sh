#!/usr/bin/env bash
# Platform cleanup only. No deletion occurs unless --apply is supplied.
set -euo pipefail
umask 077
export WORKSHOP_MANAGER_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 - "$@" <<'PY'
# coding: utf-8
"""Clean only identities recorded by init-users.sh. Requires jf, jq, Python 3.9+."""
import argparse, base64, datetime, json, os, re, shutil, subprocess, sys
from pathlib import Path
from urllib.parse import quote, urlparse

ROOT = Path(os.environ['WORKSHOP_MANAGER_DIR'])
MARKER = 'JFrog AI Catalog onsite workshop'

def main():
    parser = argparse.ArgumentParser(description='Workshop 平台清理。默认只预览；--apply 执行。无 user/project 参数时保留用户和项目。')
    parser.add_argument('targets', nargs='*', metavar='{user,project}', help='user 删除测试用户；project 删除测试项目；可同时提供')
    parser.add_argument('--server-id', required=True, help='平台管理员 CLI Server ID（Access Token 认证）')
    parser.add_argument('--platform-url', required=True, help='平台根地址，必须与创建记录和 CLI 配置一致')
    parser.add_argument('--state-file', type=Path, default=ROOT/'workshop_users.state.json')
    parser.add_argument('--agent-guard', type=Path, help='已安装的 agent-guard 可执行文件，或其 bin/cli.js')
    parser.add_argument('--apply', action='store_true', help='执行清理；不提供时仅预览')
    args = parser.parse_args()
    if set(args.targets) - {'user', 'project'}:
        parser.error('可选清理参数仅允许 user、project')
    url = args.platform_url.rstrip('/')
    parsed = urlparse(url)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment:
        parser.error('--platform-url 必须是 HTTPS 平台根地址')
    if len(args.targets) != len(set(args.targets)):
        parser.error('user/project 参数不要重复')
    for name in ('jf', 'jq'):
        if not shutil.which(name):
            parser.error('缺少 '+name+'，请先将讲师工具加入 PATH')
    state = json.loads(args.state_file.read_text(encoding='utf-8'))
    if state.get('url', '').rstrip('/') != url:
        raise RuntimeError('创建记录的平台地址不匹配，已停止')
    rows = state.get('rows')
    if not isinstance(rows, list) or not rows:
        raise RuntimeError('创建记录没有有效 rows，已停止')
    projects, users = {}, {}
    for row in rows:
        project, user = row.get('project', ''), row.get('user', '')
        if not re.fullmatch(r'project[1-9][0-9]*', project) or user != 'user'+project[7:]:
            raise RuntimeError('创建记录包含不符合 projectN/userN 规则的对象，已停止')
        if project in projects or user in users:
            raise RuntimeError('创建记录存在重复对象，已停止')
        # Failed/never-created identities are not adopted by name.
        if row.get('project_created') is True:
            projects[project] = row
        if row.get('user_created') is True:
            users[user] = row
    env = dict(os.environ, JFROG_CLI_OFFER_CONFIG='false', JFROG_CLI_LOG_LEVEL='INFO', jfcm_NO_HISTORY='1')
    env.setdefault('JFROG_CLI_USER_AGENT', 'jfrog-workshop-cleanup/1.0')
    for key in ('JFROG_ACCESS_TOKEN', 'JF_ACCESS_TOKEN', 'JFROG_URL', 'JF_URL'):
        env.pop(key, None)  # Always target the explicitly selected CLI server.
    def cli(arguments, payload=None):
        try:
            result = subprocess.run(['jf']+arguments, input=payload, capture_output=True, text=True, env=env, timeout=180)
        except subprocess.TimeoutExpired:
            raise RuntimeError('CLI 请求超时；远端结果可能已生效。核对后重新预览，不自动重试')
        lines, logs = [], []
        for line in result.stdout.splitlines():
            clean = re.sub(r'\x1b\[[0-9;]*m', '', line)
            if re.match(r'^\s*(?:\d{2}:\d{2}:\d{2}\s+)?\[(Info|Warn|Error|Debug)\]', clean, re.I):
                logs.append(clean)
            else:
                lines.append(line)
        result.stdout = '\n'.join(lines)
        result.stderr += '\n'+'\n'.join(logs)
        return result
    def parse_json(text):
        result = subprocess.run(['jq', '-c', '.'], input=text, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError('CLI/API 响应不是有效 JSON，未显示原文以免泄露凭据')
        return json.loads(result.stdout)
    exported = cli(['config', 'export', args.server_id])
    if exported.returncode:
        raise RuntimeError('无法读取指定 CLI Server 配置')
    try:
        config = parse_json(base64.b64decode(exported.stdout.strip()).decode('utf-8'))
        if not isinstance(config, dict) or (config.get('url') or '').rstrip('/') != url:
            raise ValueError()
        if not config.get('accessToken'):
            raise RuntimeError('管理员 CLI Server 必须使用 Access Token 认证')
    except (ValueError, TypeError):
        raise RuntimeError('CLI Server 平台地址不匹配或配置无效，未调用平台')
    finally:
        config = None
        exported = None
    version = cli(['--version'])
    match = re.search(r'(\d+)\.(\d+)\.(\d+)', version.stdout)
    if version.returncode or not match or tuple(map(int, match.groups())) < (2, 100, 0):
        raise RuntimeError('需要 JFrog CLI >= 2.100.0')
    def api(method, endpoint, missing=False, headers=()):
        options = ['api', '--server-id', args.server_id, '--timeout', '60', '-X', method]
        for header in headers:
            options += ['-H', header]
        response = cli(options+[endpoint])
        codes = re.findall(r'(?:HTTP(?:/\d(?:\.\d)?)?|Http Status:|returned|status(?: code)?)\s*[:=]?\s*([1-5]\d{2})\b', response.stderr, re.I)
        if not codes:
            codes = re.findall(r'^\s*([1-5]\d{2})\s*$', response.stderr, re.M)
        code = int(codes[-1]) if codes else None
        if response.returncode or (code and code >= 400):
            if missing and code == 404:
                return None
            hints = {401:'认证失败', 403:'需要平台管理员权限', 404:'接口或资源不存在，请核对当前版本接口，不会尝试猜测其他路径', 409:'资源仍有依赖', 429:'请求被限流'}
            raise RuntimeError(f'{method} {endpoint}: HTTP {code or "unknown"}; CLI exit {response.returncode}; '+hints.get(code, '请检查平台日志；响应原文已隐藏'))
        if method == 'DELETE':
            if code in (202, 207):
                raise RuntimeError(endpoint+': 删除尚在进行或仅部分成功，停止；核对后重新预览')
            if endpoint.startswith('/artifactory/api/repositories/') and response.stdout.strip():
                report = parse_json(response.stdout)
                if isinstance(report, dict) and (report.get('errors') or report.get('deleteArtifactsFailureCount', 0)):
                    raise RuntimeError(endpoint+': 制品未全部删除，已停止')
            return {}
        return parse_json(response.stdout)
    # Read-only inventory is completed before the first mutation.
    active = {}
    for project, row in projects.items():
        detail = api('GET', '/access/api/v1/projects/'+project, missing=True)
        if detail is None:
            print('SKIP 已不存在的测试项目:', project)
            continue
        if detail.get('project_key') != project or detail.get('description') != MARKER:
            raise RuntimeError(project+' 不再具有 init-users.sh 的 workshop 标记，已停止')
        active[project] = row
    delete_users = []
    if 'user' in args.targets:
        for user, row in users.items():
            detail = api('GET', '/access/api/v2/users/'+user, missing=True)
            if detail is None:
                continue
            if detail.get('username') != user or detail.get('email') != row.get('email') or detail.get('admin') or detail.get('is_admin'):
                raise RuntimeError(user+' 的身份或角色与测试记录不符，已停止')
            delete_users.append(user)
    repositories = api('GET', '/artifactory/api/repositories') if active else []
    if not isinstance(repositories, list):
        raise RuntimeError('仓库列表结构异常，已停止')
    delete_repos = []
    for item in repositories:
        key = item.get('key') if isinstance(item, dict) else None
        if not key or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', key):
            raise RuntimeError('仓库列表包含异常 key，已停止')
        detail = api('GET', '/artifactory/api/repositories/'+quote(key, safe=''))
        owner = detail.get('projectKey')
        if owner not in active:
            continue
        # Do not purge repos shared outside this workshop or federated peers.
        shared = detail.get('sharedWithProjects') or []
        if detail.get('sharedWithAllProjects') or (isinstance(shared, list) and any(p not in active for p in shared)):
            raise RuntimeError(key+' 共享给其他项目，取消共享或确认范围后再清理')
        if str(detail.get('rclass', '')).lower() == 'federated':
            raise RuntimeError(key+' 是 Federated 仓库，需要单独处理，已停止')
        delete_repos.append({'key':key, 'project':owner, 'type':detail.get('rclass'), 'packageType':detail.get('packageType')})
    guard = args.agent_guard
    if active and guard is None:
        found = shutil.which('agent-guard')
        if found:
            guard = Path(found)
        else:
            cached = list(Path.home().glob('.npm/_npx/*/node_modules/@jfrog/agent-guard/bin/cli.js'))
            if cached:
                guard = max(cached, key=lambda p:p.stat().st_mtime)
    if active and (guard is None or not guard.is_file()):
        raise RuntimeError('找不到已安装的 Agent Guard。请用 --agent-guard 指定已有可执行文件或 bin/cli.js；脚本不会下载软件')
    mcp_entries = []
    for project in active:
        command = [str(guard)]
        if guard.suffix == '.js':
            if not shutil.which('node'):
                raise RuntimeError('运行已安装的 Agent Guard 需要 node')
            command.insert(0, 'node')
        result = subprocess.run(command+['--list-available','--server',args.server_id,'--project',project], capture_output=True, text=True, env=env, timeout=120)
        if result.returncode:
            raise RuntimeError(project+' MCP 准入列表查询失败；停止，不删除仓库')
        names = []
        meaningful = [line for line in result.stdout.splitlines() if line.strip() and not re.match(r'^\s*(?:\d{2}:\d{2}:\d{2}\s+)?\[', line)]
        if not meaningful:
            raise RuntimeError(project+' MCP 列表为空响应，无法确认是否完整，已停止')
        for line in meaningful:
            cells = line.split('\t')
            if cells[0].strip().lower() == 'name':
                continue
            if re.fullmatch(r'no (?:mcp(?: servers)?|servers|mcps)(?: are)? available\.?', line.strip(), re.I):
                continue
            if len(cells) < 4 or not re.fullmatch(r'[A-Za-z0-9@][A-Za-z0-9@._:/+ -]*', cells[0]):
                raise RuntimeError(project+' MCP 列表格式不受支持，已停止')
            names.append(cells[0].strip())
        mcp_entries.extend({'project':project, 'name':name} for name in sorted(set(names)))
    plan = {'platform':url, 'server_id':args.server_id, 'projects_in_scope':sorted(active), 'mcp_approvals':mcp_entries,
            'repositories':delete_repos, 'delete_users':delete_users, 'delete_projects':sorted(active) if 'project' in args.targets else []}
    print(json.dumps(plan, ensure_ascii=False, indent=2))
    if not args.apply:
        print('PLAN ONLY: 没有执行删除。确认以上范围后，加 --apply 执行。')
        return
    audit = ROOT/('cleanup-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S')+'-'+str(os.getpid())+'.jsonl')
    def record(kind, value):
        with audit.open('a', encoding='utf-8') as out:
            out.write(json.dumps({'at':datetime.datetime.now(datetime.timezone.utc).isoformat(), 'kind':kind, 'resource':value}, ensure_ascii=False)+'\n')
    record('plan', plan)
    for entry in mcp_entries:
        # Documented project-scoped unregister API. A 404 fails closed; no guessed fallback.
        endpoint = '/api/v1/ml/registry/mcp/unregister?name='+quote(entry['name'], safe='')
        api('DELETE', endpoint, headers=('JFrog-Project-Key: '+entry['project'],))
        record('mcp_unregistered', entry)
        print('REMOVED MCP approval:', entry['project'], entry['name'])
    delete_repos.sort(key=lambda entry: (entry['type'] != 'virtual', entry['key']))
    for entry in delete_repos:
        key = entry['key']
        current = api('GET', '/artifactory/api/repositories/'+quote(key, safe=''))
        if current.get('projectKey') != entry['project']:
            raise RuntimeError(key+' 的项目归属在预览后发生变化，已停止')
        # Explicit single-repository REST deletion; no wildcard expansion.
        api('DELETE', '/artifactory/api/repositories/'+quote(key, safe=''))
        record('repository_deleted', entry)
        print('DELETED repo and all content:', key)
    for user in delete_users:
        detail = api('GET', '/access/api/v2/users/'+user)
        if detail.get('username') != user or detail.get('email') != users[user].get('email') or detail.get('admin') or detail.get('is_admin'):
            raise RuntimeError(user+' 在预览后身份或角色发生变化，已停止')
        api('DELETE', '/access/api/v2/users/'+user)
        record('user_deleted', user)
        print('DELETED user:', user)
    for project in plan['delete_projects']:
        detail = api('GET', '/access/api/v1/projects/'+project)
        if detail.get('project_key') != project or detail.get('description') != MARKER:
            raise RuntimeError(project+' 在预览后标记发生变化，已停止')
        api('DELETE', '/access/api/v1/projects/'+project)
        record('project_deleted', project)
        print('DELETED project:', project)
    record('complete', True)
    print('SUCCESS: 平台清理完成。执行记录:', audit)
    print('学员电脑的 OpenCode/MCP/Skills 安装及缓存、共享公共缓存和本地账号 Excel/创建记录未删除。')

try:
    main()
except (Exception, KeyboardInterrupt) as error:
    # API bodies/config exports are never printed. Stop on the first failure.
    if isinstance(error, (RuntimeError, FileNotFoundError)):
        print('STOP: '+str(error), file=sys.stderr)
    else:
        print('STOP: '+type(error).__name__+'；请核对配置及平台状态，未继续删除。', file=sys.stderr)
    sys.exit(1)
PY
