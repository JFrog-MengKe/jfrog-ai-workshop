'use strict';
// Serves the workshop HTML and explicitly allowlisted instruction screenshots. Instructor XLSX, scripts and secrets are never served.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process');
const env=require('./environment.cjs');
const token=crypto.randomBytes(32).toString('hex');
let origin='',job={state:'idle',logs:[],report:null},child=null;
const allowedHosts=new Set(),allowedOrigins=new Set();
const LIMIT=500;
let identity=null,starting=false;
async function readJSON(req){let text='';for await(const chunk of req){text+=chunk;if(Buffer.byteLength(text)>4096)throw Error('Request too large')}return JSON.parse(text||'{}')}
function validateIdentity(input){const u=new URL(input.url);if(u.protocol!=='https:'||u.username||u.password||u.search||u.hash||u.pathname!=='/'||!/^user[1-9][0-9]*$/.test(input.user))throw Error('Use a platform root HTTPS URL and a userN account');return {url:u.origin,user:input.user,project:'project'+input.user.slice(4)}}
function codespacesOrigin(port){const name=process.env.CODESPACE_NAME||'',domain=process.env.GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN||'',dnsName=/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$/i;if(process.env.CODESPACES!=='true'||!dnsName.test(name)||!dnsName.test(domain))return '';return `https://${name}-${port}.${domain}`.toLowerCase()}
function normalizedHost(value,protocol='http:'){try{return new URL(`${protocol}//${value}`).host.toLowerCase()}catch{return ''}}
function isLoopback(address){return address==='127.0.0.1'||address==='::1'||address==='::ffff:127.0.0.1'}
function requestHost(req){const host=normalizedHost(req.headers.host);if(allowedHosts.has(host))return host;const forwarded=(req.headers['x-forwarded-host']||'').split(',')[0].trim(),forwardedHost=normalizedHost(forwarded,'https:');return isLoopback(req.socket.remoteAddress)&&allowedHosts.has(forwardedHost)?forwardedHost:''}
function isAllowedOrigin(value){try{return allowedOrigins.has(new URL(value).origin)}catch{return false}}
function json(res,code,obj){res.writeHead(code,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(obj));}
function equal(a,b){const x=Buffer.from(a||''),y=Buffer.from(b||'');return x.length===y.length&&crypto.timingSafeEqual(x,y)}
const server=http.createServer(async(req,res)=>{
  if(!requestHost(req))return json(res,403,{error:'Invalid host'});
  if(req.headers.origin&&!isAllowedOrigin(req.headers.origin))return json(res,403,{error:'Cross-origin request denied'});
  const languageFiles = {
    '/locales/zh-CN.json': ['locales/zh-CN.json', 'application/json; charset=utf-8'],
    '/locales/zh-TW.json': ['locales/zh-TW.json', 'application/json; charset=utf-8'],
    '/locales/en.json': ['locales/en.json', 'application/json; charset=utf-8'],
    '/scripts/i18n.js': ['scripts/i18n.js', 'text/javascript; charset=utf-8']
  };
  if (req.method === 'GET' && Object.hasOwn(languageFiles, req.url)) {
    const [file, type] = languageFiles[req.url];
    res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
    return fs.createReadStream(path.join(env.ROOT, file)).pipe(res);
  }
  const imageNames=['mcp-server.png','tools_read.png','tools_all.png','registry.png','skills-repo.png','skills-upload.png','skills-scan.png','axios-catalog.png','skills-policy-1.png','skills-policy-2.png','skills-policy-3.png','skills-policy-4.png','skills-catalog-list.png','skills-applicable-policy.png','opencode.png','jfrog-mcp.png','jfrog.png','settings.png'];
  if(req.method==='GET'&&imageNames.some(name=>req.url==='/instructions/images/'+name)){
    res.writeHead(200,{'Content-Type':'image/png','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
    return fs.createReadStream(path.join(env.ROOT,'instructions','images',req.url.split('/').pop())).pipe(res);
  }
  if(req.url==='/'||req.url==='/workshop.html'){
    if(req.method!=='GET')return json(res,405,{error:'Method not allowed'});
    res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",'Referrer-Policy':'no-referrer'});
    return fs.createReadStream(path.join(env.ROOT,'workshop.html')).pipe(res);
  }
  if(!equal(req.headers.authorization,'Bearer '+token))return json(res,403,{error:'Open the URL printed by the launcher, including #session=...'});
  if(req.method==='GET'&&req.url==='/api/status')return json(res,200,{...job,identity,platform:env.PLATFORM,base:env.BASE});
  if(req.method==='POST'&&req.url==='/api/init'){
    if(!isAllowedOrigin(req.headers.origin)||req.headers['content-type']!=='application/json')return json(res,403,{error:'Same-origin JSON request required'});
    if(child||starting)return json(res,409,{error:'An initialization is already running'});
    starting=true;
    let credentials;try{const input=await readJSON(req);identity=validateIdentity(input);if(typeof input.password!=='string'||!input.password.length||input.password.length>1024||/[\r\n\0]/.test(input.password))throw Error('请输入学员密码（不支持换行）。');credentials={password:input.password}}catch(e){starting=false;return json(res,400,{error:e.message})}
    starting=false;
    job={state:'running',logs:['正在检测操作系统与工具版本……'],report:null};
    child=cp.spawn(process.execPath,[path.join(__dirname,'environment.cjs'),'--credentials-stdin'],{cwd:env.ROOT,env:{...process.env,PATH:env.BIN+path.delimiter+process.env.PATH,WORKSHOP_PLATFORM_URL:identity.url,WORKSHOP_USER:identity.user,WORKSHOP_PROJECT:identity.project},stdio:['pipe','pipe','pipe'],windowsHide:true});
    child.stdin.on('error',()=>{});child.stdin.end(JSON.stringify(credentials));credentials.password='';
    const append=b=>{job.logs.push(...String(b).trimEnd().split('\n'));job.logs=job.logs.slice(-LIMIT)};
    child.stdout.on('data',append);child.stderr.on('data',append);
    const timer=setTimeout(()=>{append('FAILED Initialization exceeded 30 minutes; stopping installer.');child?.kill();},1800000);
    child.on('error',e=>{append('FAILED '+e.message)});
    child.on('close',code=>{clearTimeout(timer);child=null;job.state=code===0?'success':'failed';try{job.report=code===0?JSON.parse(fs.readFileSync(path.join(env.BASE,'environment-report.json'),'utf8')):env.report();job.report.lab=path.join(env.BASE,'lab_dir');job.report.envFile=path.join(env.BASE,process.platform==='win32'?'env.ps1':'env.sh');}catch{};append(code===0?'全部工具、JFrog CLI 配置及 ping 验证通过。请重新打开终端以使用新的 PATH。':'初始化未完成，请将下面的非敏感错误信息交给讲师。请检查账号密码、网络或本地安装包后重试。');});
    return json(res,202,{state:'running'});
  }
  return json(res,404,{error:'Not found'});
});
server.listen(0,'127.0.0.1',()=>{
 const port=server.address().port,localOrigin=`http://127.0.0.1:${port}`,localhostOrigin=`http://localhost:${port}`,forwardedOrigin=codespacesOrigin(port);
 origin=forwardedOrigin||localOrigin;
 for(const allowedOrigin of [localOrigin,localhostOrigin,forwardedOrigin].filter(Boolean)){const parsed=new URL(allowedOrigin);allowedHosts.add(parsed.host.toLowerCase());allowedOrigins.add(parsed.origin)}
 const localUrl=localOrigin+'/#session='+token,forwardedUrl=forwardedOrigin?forwardedOrigin+'/#session='+token:'';
 const url=forwardedUrl||localUrl;
 console.log(forwardedOrigin?'\nJFrog Workshop Codespaces 页面\n'+forwardedUrl+'\n\nJFrog Workshop 本机页面\n'+localUrl+'\n\n保持此窗口打开。按 Ctrl+C 停止。服务仅监听本机，并通过 Codespaces 转发。请勿分享含 session 的链接。\n':'\nJFrog Workshop 本机页面\n'+localUrl+'\n\n保持此窗口打开。按 Ctrl+C 停止。仅监听本机，请勿分享含 session 的链接。\n');
 if(!process.argv.includes('--no-open')){
  let executable,args;
  if(process.platform==='darwin'){executable='open';args=[url]}
  else if(process.platform==='win32'){executable='explorer.exe';args=[url]}
  else {executable='xdg-open';args=[url]}
  const opener=cp.spawn(executable,args,{stdio:'ignore',windowsHide:true});opener.on('error',()=>console.log('无法自动打开浏览器，请打开上面的本机链接。'));opener.unref();
 }
});
function stop(){child?.kill();server.close(()=>process.exit(0));setTimeout(()=>process.exit(0),1000).unref()}
process.on('SIGINT',stop);process.on('SIGTERM',stop);
