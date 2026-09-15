#!/usr/bin/env node
/**
 * mimo-linux-port: ThreadView & Scroll / Focus / IME Patcher
 * Fixes:
 * 1. Viewport rubber-banding / lock to bottom (19 pins/sec loop)
 * 2. Focus stealing to composer-input when reading history
 * 3. Wayland scroll hijacking and wheel up unstick
 */

const fs = require('fs');
const path = require('path');

const targetFile = process.argv[2];
if (!targetFile || !fs.existsSync(targetFile)) {
  console.error('Usage: node patch.js <path-to-ThreadView-*.js>');
  process.exit(1);
}

let code = fs.readFileSync(targetFile, 'utf8');

const edits = [
  {
    name: 'onScroll logic fix',
    target: `onScroll(n,e,u,l,v=!1){const g=n<=e&&!v;this.lastGeometry={scrollTop:l?.scrollTop??this.el?.scrollTop??0,clientHeight:l?.clientHeight??this.el?.clientHeight??0,scrollHeight:l?.scrollHeight??this.el?.scrollHeight??0,dist:n,threshold:e};const b=Lt(!this.following,u,g),k=Mt(u,b);k!==this.following?this.setFollow(k,k?"scroll-to-bottom":"user-scroll-up"):k&&g&&this.setFollow(!0,"scroll-to-bottom")}`,
    replacement: `onScroll(n,e,u,l,v=!1){this.lastGeometry={scrollTop:l?.scrollTop??this.el?.scrollTop??0,clientHeight:l?.clientHeight??this.el?.clientHeight??0,scrollHeight:l?.scrollHeight??this.el?.scrollHeight??0,dist:n,threshold:e};if(v)return;if(u||n>25){this.setFollow(!1,"user-scroll-up")}else if(n<=15){this.setFollow(!0,"scroll-to-bottom")}}`
  },
  {
    name: 'pinNow invariant guard',
    target: `pinNow(n){if(!this.following||this.suppressPin)return this.push({t:Date.now(),kind:"pin",source:n,ok:!1,why:this.following?this.suppressWhy??"hold-select":"away-from-bottom"}),!1;if(!this.el)return this.push({t:Date.now(),kind:"pin",source:n,ok:!0}),!0;const e=this.el.scrollTop;this.el.scrollTop=this.el.scrollHeight;`,
    replacement: `pinNow(n){if(!this.following||this.suppressPin)return this.push({t:Date.now(),kind:"pin",source:n,ok:!1,why:this.following?this.suppressWhy??"hold-select":"away-from-bottom"}),!1;if(!this.el)return this.push({t:Date.now(),kind:"pin",source:n,ok:!0}),!0;const _d=this.el.scrollHeight-this.el.scrollTop-this.el.clientHeight;if(_d>25&&n!=="turn-start"&&n!=="switch-convo"&&n!=="jump-to-bottom"){this.setFollow(!1,"away-from-bottom");return this.push({t:Date.now(),kind:"pin",source:n,ok:!1,why:"away-from-bottom"}),!1;}const e=this.el.scrollTop;this.el.scrollTop=this.el.scrollHeight;`
  },
  {
    name: 'wheel up immediate detachment',
    target: `const s=o=>{o.deltaY<0&&(re.current=Date.now())};`,
    replacement: `const s=o=>{o.deltaY<0&&(re.current=Date.now(),h.setFollow(!1,"user-wheel-up"))};`
  },
  {
    name: 'Qt scroll hijacking bypass',
    target: `!G.getState().findOpen&&Qt(O,h.following,s,w,o,d,i,S)`,
    replacement: `!G.getState().findOpen&&!1`
  },
  {
    name: 'tt click conditional focus',
    target: `Ft(t.target,s?s.toString():"")&&Ct()`,
    replacement: `h.following&&Ft(t.target,s?s.toString():"")&&Ct()`
  },
  {
    name: 'ro f.current distance guard',
    target: `qt(h.following)&&h.suppressWhy!=="reveal"&&!x()&&!He()&&(t.scrollTop=t.scrollHeight)`,
    replacement: `qt(h.following)&&(t.scrollHeight-t.scrollTop-t.clientHeight<=25)&&h.suppressWhy!=="reveal"&&!x()&&!He()&&(t.scrollTop=t.scrollHeight)`
  }
];

let applied = 0;
for (const edit of edits) {
  if (code.includes(edit.replacement)) {
    console.log(`[INFO] Patch '${edit.name}' already applied, skipping.`);
    applied++;
    continue;
  }
  if (!code.includes(edit.target)) {
    console.warn(`[WARN] Target pattern for '${edit.name}' not found, skipping.`);
    continue;
  }
  code = code.replace(edit.target, edit.replacement);
  applied++;
  console.log(`[OK] Applied patch: ${edit.name}`);
}

if (applied > 0) {
  fs.writeFileSync(targetFile, code, 'utf8');
  console.log(`[SUCCESS] Patched ${targetFile} successfully.`);
} else if (!path.basename(targetFile).includes('index.mjs')) {
  console.error('[ERROR] No patches could be applied.');
  process.exit(1);
}

// -----------------------------------------------------------------------------
// Also patch main/index.mjs for Linux machine-id if present
// -----------------------------------------------------------------------------
function patchMainIndex(filePath) {
  if (!fs.existsSync(filePath)) return;
  let mainCode = fs.readFileSync(filePath, 'utf8');
  const target = 'function Nj(){if(process.platform==="win32"){';
  const replacement = 'function Nj(){if(process.platform==="linux"){try{const t=X.readFileSync("/etc/machine-id","utf8").trim();if(t&&!bl(t))return t}catch{}try{const t=X.readFileSync("/var/lib/dbus/machine-id","utf8").trim();if(t&&!bl(t))return t}catch{}}if(process.platform==="win32"){';
  if (mainCode.includes(replacement)) {
    console.log("[INFO] Patch 'Linux machine-id deviceId fix' already applied to main/index.mjs.");
    return;
  }
  if (mainCode.includes(target)) {
    mainCode = mainCode.replace(target, replacement);
    fs.writeFileSync(filePath, mainCode, 'utf8');
    console.log("[OK] Applied patch: Linux machine-id deviceId fix to main/index.mjs");
  }
}

if (path.basename(targetFile) === 'index.mjs') {
  patchMainIndex(targetFile);
} else {
  const candidateMain = path.resolve(path.dirname(targetFile), '../../main/index.mjs');
  patchMainIndex(candidateMain);
}

