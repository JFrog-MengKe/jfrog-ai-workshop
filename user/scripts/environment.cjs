'use strict';
// Dependency-free installer: prefer local tools, download missing official releases.
const fs=require('node:fs'), path=require('node:path'), os=require('node:os');
const crypto=require('node:crypto'), cp=require('node:child_process'), zlib=require('node:zlib');
const ROOT=path.resolve(__dirname,'..');
const cache=require('./package-cache.cjs').createCache();
const BASE=path.resolve(process.env.WORKSHOP_HOME||path.join(os.homedir(),'.jfrog-workshop'));
const BIN=path.join(BASE,'bin');
const PLATFORM=`${process.platform}-${process.arch}`;
const EXT=process.platform==='win32'?'.exe':'';
const MIN={opencode:'1.17.7',node:'18.0.0',npx:'6.0.0',jf:'2.100.0',jq:'1.6.0',curl:'7.64.0'};
const NAMES=Object.keys(MIN);
const PATH_ENV=()=>({...process.env,PATH:BIN+path.delimiter+process.env.PATH,JFROG_CLI_OFFER_CONFIG:'false'});
function log(s){console.log(s)}
function version(s){const m=String(s).match(/(?:^|[^\d])(\d+)\.(\d+)(?:\.(\d+))?/);return m?[+m[1],+m[2],+(m[3]||0)]:null}
function ge(a,b){a=version(a);b=version(b);if(!a||!b)return false;for(let i=0;i<3;i++){if(a[i]!==b[i])return a[i]>b[i]}return true}
function run(file,args,options={}){const r=cp.spawnSync(file,args,{encoding:'utf8',env:PATH_ENV(),timeout:30000,windowsHide:true,...options});if(r.error||r.status!==0)throw Error(`${path.basename(file)} failed: ${r.error?.message||String(r.stderr).slice(0,700)}`);return String(r.stdout).trim()}
function locate(name){const files=process.platform==='win32'?(name==='npx'?['npx.cmd']: [name+'.exe']):[name];for(const dir of PATH_ENV().PATH.split(path.delimiter)){for(const file of files){const p=path.join(dir,file);try{fs.accessSync(p,fs.constants.X_OK);return p}catch{}}}return null}
function inspect(name){const file=locate(name);let output='',error='';try{if(!file)throw Error('not found on PATH');output=name==='npx'&&process.platform==='win32'?run('cmd.exe',['/d','/s','/c',`""${file}" --version"`]):run(file,['--version']);}catch(e){error=e.message}const v=version(output);let ok=!error&&ge(output,MIN[name]);if((name==='opencode'&&v?.[0]!==1)||(name==='jf'&&v?.[0]!==2))ok=false;return {name,path:file,version:v?.join('.')||null,minimum:MIN[name],ok,error}}
function report(){return {platform:PLATFORM,tools:NAMES.map(inspect),base:BASE,bin:BIN}}
function hash(file){return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')}
function checked(file){if(!fs.existsSync(file))throw Error('Missing package: '+file);return cache.local(file)}
function copyChecked(src,dest){checked(src);fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(src,dest);fs.chmodSync(dest,0o755)}
function treeChecked(src,dest){for(const ent of fs.readdirSync(src,{withFileTypes:true})){const a=path.join(src,ent.name),b=path.join(dest,ent.name);if(ent.isSymbolicLink())throw Error('Portable bundles must not contain symlinks: '+a);if(ent.isDirectory()){fs.mkdirSync(b,{recursive:true});treeChecked(a,b)}else copyChecked(a,b)}}
// Extract only one executable from a ZIP; no archive paths are written to disk.
function zipExecutable(file,basename,dest){const b=fs.readFileSync(checked(file));let end=-1;for(let i=b.length-22;i>=Math.max(0,b.length-65557);i--){if(b.readUInt32LE(i)===0x06054b50){end=i;break}}if(end<0)throw Error('Invalid ZIP');let off=b.readUInt32LE(end+16);const count=b.readUInt16LE(end+10);for(let i=0;i<count;i++){if(b.readUInt32LE(off)!==0x02014b50)throw Error('Bad ZIP directory');const flags=b.readUInt16LE(off+8),method=b.readUInt16LE(off+10),size=b.readUInt32LE(off+20),plain=b.readUInt32LE(off+24),nl=b.readUInt16LE(off+28),el=b.readUInt16LE(off+30),cl=b.readUInt16LE(off+32),at=b.readUInt32LE(off+42);const name=b.subarray(off+46,off+46+nl).toString('utf8');off+=46+nl+el+cl;if(name.split('/').pop()!==basename)continue;if(flags&1||plain>300*1024*1024)throw Error('Unsupported/encrypted ZIP');if(b.readUInt32LE(at)!==0x04034b50)throw Error('Bad ZIP header');const start=at+30+b.readUInt16LE(at+26)+b.readUInt16LE(at+28);const data=b.subarray(start,start+size);const out=method===0?data:method===8?zlib.inflateRawSync(data,{maxOutputLength:300*1024*1024}):null;if(!out||out.length!==plain)throw Error('ZIP decompression failed');fs.writeFileSync(dest,out,{mode:0o755});return}throw Error(`${basename} not found inside ${file}`)}
function tarExecutable(file,basename,dest){
checked(file);
const names=run('tar',['-tzf',file]).split('\n');
const member=names.find(n=>n.split('/').pop()===basename);
if(!member)throw Error(basename+' not found in '+file);
const r=cp.spawnSync('tar',['-xOzf',file,member],{env:PATH_ENV(),maxBuffer:300*1024*1024,timeout:60000});
if(r.error||r.status!==0)throw Error('Could not extract '+basename);
fs.writeFileSync(dest,r.stdout,{mode:0o755});
}
async function installBinary(name){
const packageFile=await cache.ensure(name),stage=fs.mkdtempSync(path.join(BASE,'stage-')),dest=path.join(stage,name+EXT);
try{
 if(packageFile.endsWith('.zip'))zipExecutable(packageFile,name+EXT,dest);
 else if(packageFile.endsWith('.tar.gz'))tarExecutable(packageFile,name+EXT,dest);
 else copyChecked(packageFile,dest);
 const output=run(dest,['--version']),v=version(output);
 if(!ge(output,MIN[name])||(name==='opencode'&&v?.[0]!==1)||(name==='jf'&&v?.[0]!==2))throw Error('Package '+name+' does not meet version requirement ('+output+')');
 fs.renameSync(dest,path.join(BIN,name+EXT));log('INSTALLED '+name+' '+v.join('.'));
}finally{fs.rmSync(stage,{recursive:true,force:true})}
}
function installNode(){// Launcher performs this step too; keep a single shell/PowerShell implementation.
const script=process.platform==='win32'?'bootstrap-node.ps1':'bootstrap-node.sh';const exe=process.platform==='win32'?'powershell.exe':'bash';const args=process.platform==='win32'?['-NoProfile','-File',path.join(__dirname,script),'-ForceInstall']: [path.join(__dirname,script),'--force'];const r=cp.spawnSync(exe,args,{stdio:'inherit',env:PATH_ENV()});if(r.status!==0)throw Error('Node / npx installation failed');}
async function installCurl(){
const src=path.join(ROOT,'tools',PLATFORM,'curl'),dest=path.join(BASE,'curl');
if(fs.existsSync(src)){
 log('LOCAL tools/'+PLATFORM+'/curl');treeChecked(src,dest);
}else if(process.platform==='darwin'&&fs.existsSync('/usr/bin/curl')&&ge(run('/usr/bin/curl',['--version']),MIN.curl)){
 // Reuse a valid system curl if an older PATH entry shadows it.
 fs.mkdirSync(path.join(dest,'bin'),{recursive:true});
 fs.writeFileSync(path.join(dest,'bin','curl'),'#!/bin/sh\nexec /usr/bin/curl "$@"\n',{mode:0o755});
 log('LOCAL existing system curl /usr/bin/curl');
}else{
 const archive=await cache.ensure('curl');
 fs.mkdirSync(dest,{recursive:true});
 if(process.platform==='win32'){
  fs.mkdirSync(path.join(dest,'bin'),{recursive:true});
  zipExecutable(archive,'curl.exe',path.join(dest,'bin','curl.exe'));
  try{zipExecutable(archive,'curl-ca-bundle.crt',path.join(dest,'bin','curl-ca-bundle.crt'))}catch(e){if(!e.message.includes('not found inside'))throw e}
 }else{
  if(!locate('cc')||!locate('make'))throw Error('curl source is cached in tools. Building it requires a C compiler, make and OpenSSL development files; ask the instructor to prepare them or provide tools/'+PLATFORM+'/curl/bin/curl.');
  const stage=fs.mkdtempSync(path.join(BASE,'curl-build-'));
  try{
   const names=run('tar',['-tzf',archive]).split('\n');
   if(names.some(n=>n.startsWith('/')||n.split('/').includes('..')))throw Error('Unsafe curl archive path');
   run('tar',['-xzf',archive,'-C',stage,'--strip-components=1'],{timeout:60000});
   log('BUILD curl from official source (requires compiler and OpenSSL headers)');
   for(const [file,args] of [['sh',['./configure','--prefix='+dest,'--with-openssl','--disable-shared','--without-libpsl']],['make',['-j'+Math.min(os.cpus().length,4)]],['make',['install']]]){
    const r=cp.spawnSync(file,args,{cwd:stage,env:PATH_ENV(),stdio:'inherit',timeout:1200000});
    if(r.error||r.status!==0)throw Error('curl build failed; check compiler / OpenSSL dependencies. Official source remains cached in tools.');
   }
  }finally{fs.rmSync(stage,{recursive:true,force:true})}
 }
}
const executable=path.join(dest,'bin','curl'+EXT),output=run(executable,['--version']);
if(!ge(output,MIN.curl))throw Error('curl does not meet minimum version');
if(process.platform==='win32'){
 for(const ent of fs.readdirSync(path.join(dest,'bin'))){const file=path.join(dest,'bin',ent);if(fs.statSync(file).isFile())fs.copyFileSync(file,path.join(BIN,ent))}
}else{
 fs.writeFileSync(path.join(BIN,'curl'),'#!/usr/bin/env bash\nexec '+"'"+executable.replaceAll("'","'\\''")+"'"+' "$@"\n',{mode:0o755});
}
log('INSTALLED curl '+version(output).join('.'));
}
function configure(){
const identity={url:process.env.WORKSHOP_PLATFORM_URL||'',user:process.env.WORKSHOP_USER||'',project:process.env.WORKSHOP_PROJECT||''};
const quote=s=>"'"+s.replaceAll("'","'\\''")+"'";
let identityEnv='';
if(identity.url||identity.user){
 if(!/^https:\/\/[^/?#@]+$/.test(identity.url)||!/^user[1-9][0-9]*$/.test(identity.user)||identity.project!=='project'+identity.user.slice(4))throw Error('Invalid workshop identity');
 const entries={JFROG_PLATFORM_URL:identity.url,WORKSHOP_USER:identity.user,WORKSHOP_PROJECT:identity.project,JFROG_CLI_SERVER_ID:'workshop-'+identity.user};
 identityEnv=Object.entries(entries).map(([k,v])=>process.platform==='win32'?`$env:${k} = '${v.replaceAll("'","''")}'`:`export ${k}=${quote(v)}`).join('\n')+'\n';
 fs.writeFileSync(path.join(BASE,'workshop.json'),JSON.stringify(identity,null,2),{mode:0o600});
}
const envFile=path.join(BASE,process.platform==='win32'?'env.ps1':'env.sh');const content=process.platform==='win32'?`$env:PATH = '${BIN.replaceAll("'","''")}'+[IO.Path]::PathSeparator+$env:PATH\n`:`export PATH='${BIN.replaceAll("'","'\\''")}':"$PATH"\n`;fs.writeFileSync(envFile,content+identityEnv,{mode:0o600});if(process.platform==='win32'){const command='$p=[Environment]::GetEnvironmentVariable("Path","User");$b=$args[0];if(($p -split ";") -notcontains $b){[Environment]::SetEnvironmentVariable("Path",$b+";"+$p,"User")}';const ps=command.replace('$b=$args[0]',`$b='${BIN.replaceAll("'","''")}'`);run('powershell.exe',['-NoProfile','-EncodedCommand',Buffer.from(ps,'utf16le').toString('base64')]);}
else{const profile=process.env.SHELL?.endsWith('/zsh')?'.zshrc':'.bashrc';const file=path.join(os.homedir(),profile);const line=`\n# JFrog workshop tools\n[ ! -f '${envFile.replaceAll("'","'\\''")}'] || . '${envFile.replaceAll("'","'\\''")}'\n`;const existing=fs.existsSync(file)?fs.readFileSync(file,'utf8'):'';if(!existing.includes(envFile))fs.appendFileSync(file,line,{mode:0o600});if(process.platform==='darwin'&&profile==='.bashrc'){const login=path.join(os.homedir(),'.bash_profile');const text=fs.existsSync(login)?fs.readFileSync(login,'utf8'):'';if(!text.includes(envFile))fs.appendFileSync(login,line,{mode:0o600});}}
const lab=path.join(BASE,'lab_dir');fs.mkdirSync(lab,{recursive:true});if(!fs.existsSync(path.join(lab,'readme.txt')))fs.writeFileSync(path.join(lab,'readme.txt'),'Hello JFrog Workshop\n');log('CONFIGURED PATH and lab directory: '+lab);return {envFile,lab}}
function configureJFrog(password){
 const user=process.env.WORKSHOP_USER,url=process.env.WORKSHOP_PLATFORM_URL,project=process.env.WORKSHOP_PROJECT;
 if(typeof password!=='string'||!password.length||password.length>1024||/[\r\n\0]/.test(password))throw Error('请输入有效的学员密码（不支持换行）。');
 const serverId='workshop-'+user,jf=locate('jf');
 const invoke=(args,input,label)=>{
  const r=cp.spawnSync(jf,args,{encoding:'utf8',input,env:{...PATH_ENV(),jfcm_NO_HISTORY:'1'},timeout:60000,windowsHide:true});
  // Never forward CLI authentication output: it can contain credentials or tokens.
  if(r.error||r.status!==0){const http=String(r.stderr).match(/(?:HTTP[\/\d.]*\s+|status(?: code)?[ :]+)([1-5][0-9]{2})/i);const output=String(r.stderr);const status=http?.[1]||output.match(/\b(?:400|401|403|404|409|429|500|502|503|504)\b/)?.[0];const category=/authenticating with access token is currently mandatory/i.test(output)?'CLI 命令要求已有 Access Token':/flag provided but not defined|unknown flag/i.test(output)?'CLI 参数不受支持':/timeout|deadline|ETIMEDOUT/i.test(output)?'网络请求超时':/certificate|x509/i.test(output)?'TLS 证书验证失败':/no such host|ENOTFOUND/i.test(output)?'域名解析失败':null;const reason=status?'HTTP '+status:category||r.error?.code||'CLI exit '+r.status;throw Error(label+'失败（'+reason+'），请检查平台 URL、学员账号、密码及网络后重试。');}
  return String(r.stdout).trim();
 };
 log('CONFIGURE JFrog CLI '+serverId+' / '+user);
 // Keep bootstrap credentials only in the CLI credential store, then replace with a token.
 // Access token issuance needs the original password, not Artifactory's encrypted password.
 let bootstrap=false,tokenSaved=false;
 try{
  invoke(['c','add','--url='+url,'--user='+user,'--password-stdin','--enc-password=false','--basic-auth-only=true','--interactive=false','--overwrite',serverId],password+'\n','临时账号认证配置');
  bootstrap=true;password='';
  log('CREATE Access Token for '+user+' (24 hours)');
  const raw=invoke(['api','--server-id='+serverId,'--timeout=30','-X','POST','-H','Content-Type: application/json','--input','-','/access/api/v1/tokens'],JSON.stringify({grant_type:'client_credentials',username:user,scope:'applied-permissions/user',expires_in:86400,refreshable:false,description:'JFrog AI Catalog Workshop'}),'Access Token 签发（平台需允许内部用户通过密码创建 Token，且不能启用 MFA）');
  const parsed=cp.spawnSync(locate('jq'),['-er','.access_token | select(type == "string" and length > 0)'],{encoding:'utf8',input:raw,env:PATH_ENV(),timeout:10000,windowsHide:true});
  if(parsed.error||parsed.status!==0)throw Error('Token 签发响应无效，未能取得 access_token。');
  let token=parsed.stdout.trim();
  invoke(['c','add','--url='+url,'--user='+user,'--access-token-stdin','--interactive=false','--overwrite',serverId],token+'\n','Access Token 认证配置');
  token='';tokenSaved=true;
 }finally{
  password='';
  if(bootstrap&&!tokenSaved){
   // Never leave the temporary plaintext password behind after failed issuance.
   try{invoke(['c','remove','--quiet',serverId],undefined,'临时密码配置清理')}catch{throw Error('Token 配置失败，临时密码清理也失败。请执行 jf c remove '+serverId+'，再联系讲师。')}
  }
 }
 const body=invoke(['api','--server-id='+serverId,'--timeout=30','-X','GET','/access/api/v1/projects/'+project],undefined,'Token 项目访问验证');
 const projectResult=cp.spawnSync(locate('jq'),['-er','--arg','project',project,'.project_key == $project'],{encoding:'utf8',input:body,env:PATH_ENV(),timeout:10000,windowsHide:true});
 if(projectResult.error||projectResult.status!==0)throw Error('Token 项目访问验证失败，请确认本人对应项目和权限。');
 log('PASS Access Token project access: '+project);
 const ping=invoke(['rt','ping','--server-id='+serverId],undefined,'jf rt ping');
 let pingOK=ping==='OK';try{const parsed=JSON.parse(ping);pingOK=parsed.status==='OK'}catch{}
 if(!pingOK)throw Error('jf rt ping 未返回 OK，请检查平台连接。');
 invoke(['c','use',serverId],undefined,'设置当前 JFrog CLI Server');
 log('PASS JFrog CLI configured: '+serverId+' / '+user);log('PASS jf rt ping --server-id '+serverId+': OK');
 return {ok:true,serverId,user,project,ping:'OK',authType:'access-token',projectVerified:true,tokenExpiresIn:86400};
}
async function install(credentials){if(!['darwin-arm64','darwin-x64','linux-arm64','linux-x64','win32-arm64','win32-x64'].includes(PLATFORM))throw Error('Unsupported OS/CPU: '+PLATFORM);fs.mkdirSync(BIN,{recursive:true});log('DETECTED '+PLATFORM);let node=inspect('node'),npx=inspect('npx');if(!node.ok||!npx.ok)installNode();else{log('SKIP node '+node.version);log('SKIP npx '+npx.version)}for(const name of ['opencode','jf','jq','curl']){const r=inspect(name);if(r.ok){log('SKIP '+name+' '+r.version);continue}log('INSTALL '+name+' (missing or incompatible)');if(name==='curl')await installCurl();else await installBinary(name)}const config=configure();const authentication=credentials?configureJFrog(credentials.password):null;if(credentials)credentials.password='';const result={...report(),...config,authentication,completedAt:new Date().toISOString()};result.ok=result.tools.every(t=>t.ok);fs.writeFileSync(path.join(BASE,'environment-report.json'),JSON.stringify(result,null,2),{mode:0o600});for(const t of result.tools)log(`${t.ok?'PASS':'FAIL'} ${t.name}: ${t.version||t.error}`);if(!result.ok)throw Error('Final verification failed');log('SUCCESS Environment initialized');return result}
module.exports={ROOT,BASE,BIN,PLATFORM,MIN,NAMES,report,install,hash,checked,configureJFrog};
if(require.main===module){if(process.argv.includes('--check')){const r=report();console.log(JSON.stringify(r,null,2));process.exitCode=r.tools.every(t=>t.ok)?0:1}else (async()=>{let credentials;if(process.argv.includes('--credentials-stdin')){let input='';for await(const chunk of process.stdin){input+=chunk;if(input.length>4096)throw Error('Credential input too large')}credentials=JSON.parse(input);input=''}await install(credentials)})().catch(e=>{console.error('FAILED '+e.message);process.exitCode=1})}
