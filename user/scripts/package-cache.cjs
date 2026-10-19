'use strict';
// Official release downloads, retained under user/tools/<OS>-<CPU>.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const https = require('node:https');
const {pipeline} = require('node:stream/promises');
const VERSIONS = {node:'24.22.0', opencode:'1.19.3', jf:'2.127.0', jq:'1.8.2', curl:'8.23.0'};

function createCache(options = {}) {
  const root = options.root || path.resolve(__dirname, '..', 'tools');
  const platform = options.platform || `${process.platform}-${process.arch}`;
  const [system, arch] = platform.split('-');
  if (!['darwin','linux','win32'].includes(system) || !['arm64','x64'].includes(arch)) throw Error('Unsupported platform: '+platform);
  const folder = path.join(root, platform);
  const manifestPath = path.join(root, 'checksums.json');
  const log = options.log || console.log;
  const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  const manifest = () => fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath,'utf8')) : {algorithm:'sha256',files:{},sources:{}};
  const keyFor = file => {
    const key = path.relative(root,file).split(path.sep).join('/');
    if (key.startsWith('../') || path.isAbsolute(key)) throw Error('Package is outside tools directory');
    return key;
  };
  function remember(file, sha, source = {}) {
    const data = manifest(), key = keyFor(file);
    data.files ||= {}; data.sources ||= {};
    data.files[key] = sha;
    data.sources[key] = {...data.sources[key],...source,sha256:sha};
    fs.mkdirSync(root,{recursive:true});
    const temp=manifestPath+'.'+process.pid+'.tmp';
    fs.writeFileSync(temp,JSON.stringify(data,null,2)+'\n');
    fs.renameSync(temp,manifestPath);
  }
  function local(file) {
    const data = manifest(), key = keyFor(file);
    let expected = data.files?.[key];
    if (!expected && fs.existsSync(file+'.sha256')) expected = fs.readFileSync(file+'.sha256','utf8').match(/\b[a-fA-F0-9]{64}\b/)?.[0];
    const actual=digest(file);
    if (expected && expected.toLowerCase()!==actual) throw Error('SHA256 mismatch for local package: '+key+'; remove/replace the damaged file before retrying.');
    // A manually supplied local package is an explicit user input. Record its
    // integrity hash if no distribution checksum accompanied it; never replace
    // an existing mismatching checksum. Installed version is verified separately.
    if (!expected) log('LOCAL HASH '+key+' (manually supplied package)');
    remember(file,actual,expected ? {} : {origin:'local'});
    log('LOCAL '+key);
    return file;
  }
  function executable(name) {
    const names=process.platform==='win32'?[name+'.exe']:[name];
    for (const directory of (process.env.PATH||'').split(path.delimiter)) for (const leaf of names) {
      const file=path.join(directory,leaf);
      try {fs.accessSync(file,fs.constants.X_OK);return file;} catch {}
    }
    return null;
  }
  async function command(file,args) {
    await new Promise((resolve,reject)=>{
      const child=cp.spawn(file,args,{stdio:['ignore','inherit','inherit'],windowsHide:true});
      child.on('error',reject);
      child.on('close',code=>code===0?resolve():reject(Error(path.basename(file)+' download failed (exit '+code+')')));
    });
  }
  async function nativeDownload(url,destination,depth=0) {
    if (depth>8) throw Error('Too many HTTPS redirects');
    const response=await new Promise((resolve,reject)=>{
      const req=https.get(url,{headers:{'User-Agent':'jfrog-workshop/1.0'}},resolve);
      req.setTimeout(60000,()=>req.destroy(Error('HTTPS download timed out')));
      req.on('error',reject);
    });
    if ([301,302,303,307,308].includes(response.statusCode)) {
      response.resume();const next=new URL(response.headers.location,url);
      if(next.protocol!=='https:') throw Error('Refusing non-HTTPS redirect');
      return nativeDownload(next.href,destination,depth+1);
    }
    if(response.statusCode!==200){response.resume();throw Error('Official download returned HTTP '+response.statusCode);}
    await pipeline(response,fs.createWriteStream(destination));
  }
  const transport = options.fetchFile || (async (url,destination)=>{
    if(new URL(url).protocol!=='https:') throw Error('Only official HTTPS downloads are supported');
    const curl=executable('curl'), wget=executable('wget');
    if(curl) return command(curl,['--fail','--location','--silent','--show-error','--proto','=https','--retry','2','--connect-timeout','15','--max-time','900','--user-agent','jfrog-workshop/1.0','--output',destination,url]);
    if(wget) return command(wget,['--https-only','--timeout=60','--tries=3','--user-agent=jfrog-workshop/1.0','--output-document='+destination,url]);
    if(process.platform==='win32') {
      const quote=s=>"'"+s.replaceAll("'","''")+"'";
      const script="$ErrorActionPreference='Stop'; Invoke-WebRequest -UseBasicParsing -Uri "+quote(url)+' -OutFile '+quote(destination);
      return command('powershell.exe',['-NoProfile','-EncodedCommand',Buffer.from(script,'utf16le').toString('base64')]);
    }
    return nativeDownload(url,destination);
  });
  async function text(url) {
    fs.mkdirSync(folder,{recursive:true});
    const temp=path.join(folder,'.metadata-'+process.pid+'-'+crypto.randomBytes(4).toString('hex'));
    try {await transport(url,temp);return fs.readFileSync(temp,'utf8');}
    finally {fs.rmSync(temp,{force:true});}
  }
  async function github(repo,tag,asset) {
    const release=JSON.parse(await text(`https://api.github.com/repos/${repo}/releases/tags/${tag}`));
    const entry=release.assets?.find(a=>a.name===asset);
    if(!entry) throw Error(`Official release ${repo}/${tag} has no ${asset}; no other source will be substituted.`);
    let sha=entry.digest?.match(/^sha256:([a-f0-9]{64})$/i)?.[1];
    if(!sha) {
      const sums=release.assets.find(a=>/^(sha256sum\.txt|checksums\.txt|sha256sums(?:\.txt)?)$/i.test(a.name));
      if(sums) sha=(await text(`https://github.com/${repo}/releases/download/${tag}/${sums.name}`)).split('\n').find(line=>line.trim().endsWith(asset))?.match(/\b[a-f0-9]{64}\b/i)?.[0];
    }
    if(!sha) throw Error('Official SHA256 not available for '+asset);
    return {url:`https://github.com/${repo}/releases/download/${tag}/${asset}`,sha256:sha,version:tag.replace(/^v/,'')};
  }
  async function source(name) {
    if(name==='node') {
      const filename=`node-v${VERSIONS.node}-${system==='win32'?'win':system}-${arch}.${system==='win32'?'zip':'tar.gz'}`;
      const base=`https://nodejs.org/download/release/v${VERSIONS.node}/`;
      const line=(await text(base+'SHASUMS256.txt')).split('\n').find(line=>line.trim().endsWith(' '+filename));
      const sha=line?.match(/^[a-f0-9]{64}/i)?.[0];
      if(!sha) throw Error('Node archive SHA256 not published for '+filename);
      return {url:base+filename,sha256:sha,version:VERSIONS.node};
    }
    if(name==='opencode') return github('anomalyco/opencode','v'+VERSIONS.opencode,`opencode-${system==='win32'?'windows':system}-${arch}.${system==='linux'?'tar.gz':'zip'}`);
    if(name==='jq') return github('jqlang/jq','jq-'+VERSIONS.jq,`jq-${system==='darwin'?'macos':system==='win32'?'windows':'linux'}-${arch==='x64'?'amd64':'arm64'}${system==='win32'?'.exe':''}`);
    if(name==='jf') {
      const target=system==='darwin'?(arch==='x64'?'mac-386':'mac-arm64'):(system==='win32'?'windows':'linux')+'-'+(arch==='x64'?'amd64':'arm64');
      const item=`v2-jf/${VERSIONS.jf}/jfrog-cli-${target}/jf${system==='win32'?'.exe':''}`;
      const metadata=JSON.parse(await text('https://releases.jfrog.io/artifactory/api/storage/jfrog-cli/'+item));
      if(!/^[a-f0-9]{64}$/i.test(metadata.checksums?.sha256||'')) throw Error('JFrog CLI upstream checksum missing');
      return {url:'https://releases.jfrog.io/artifactory/jfrog-cli/'+item,sha256:metadata.checksums.sha256,version:VERSIONS.jf};
    }
    if(name==='curl') {
      if(system==='win32') {
        const filename=`curl-${VERSIONS.curl}_1-win64${arch==='arm64'?'a':''}-mingw.zip`;
        const url=`https://curl.se/windows/dl-${VERSIONS.curl}_1/${filename}`;
        const sha=(await text(url+'.txt')).match(/\b[a-f0-9]{64}\b/i)?.[0];
        if(!sha) throw Error('curl upstream checksum missing');
        return {url,sha256:sha,version:VERSIONS.curl};
      }
      return github('curl/curl','curl-'+VERSIONS.curl.replaceAll('.','_'),`curl-${VERSIONS.curl}.tar.gz`);
    }
    throw Error('Unsupported tool '+name);
  }
  function candidates(name) {
    const exe=system==='win32'?'.exe':'';
    if(name==='node')return [system==='win32'?'node.zip':'node.tar.gz'];
    if(name==='opencode')return ['opencode'+exe,'opencode.zip','opencode.tar.gz'];
    if(name==='curl')return [system==='win32'?'curl.zip':'curl.tar.gz'];
    return [name+exe];
  }
  async function ensure(name) {
    fs.mkdirSync(folder,{recursive:true});
    for(const filename of candidates(name)) {
      const file=path.join(folder,filename);
      if(fs.existsSync(file))return local(file);
    }
    const target=path.join(folder,name==='node'?(system==='win32'?'node.zip':'node.tar.gz'):name==='opencode'?(system==='linux'?'opencode.tar.gz':'opencode.zip'):name==='curl'?(system==='win32'?'curl.zip':'curl.tar.gz'):name+(system==='win32'?'.exe':''));
    const info=await source(name),partial=target+'.partial';
    log(`DOWNLOAD ${name} ${info.version} → tools/${platform}/${path.basename(target)}`);
    try {
      await transport(info.url,partial);
      if(digest(partial)!==info.sha256.toLowerCase())throw Error('Downloaded SHA256 mismatch for '+name);
      fs.renameSync(partial,target);
      if(['jf','jq'].includes(name))fs.chmodSync(target,0o755);
      remember(target,info.sha256,info);
      fs.writeFileSync(target+'.sha256',info.sha256+'\n');
      log('CACHED '+keyFor(target)+' (SHA256 verified)');
      return target;
    } finally {fs.rmSync(partial,{force:true});}
  }
  return {ensure,local,remember,source,folder,platform,root};
}
module.exports={createCache,VERSIONS};
if(require.main===module)createCache().ensure(process.argv[2]||'node').catch(error=>{console.error('FAILED '+error.message);process.exitCode=1;});
