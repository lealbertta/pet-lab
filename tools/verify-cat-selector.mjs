import fs from 'node:fs/promises';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import assert from 'node:assert/strict';
const execute=promisify(execFile),root=process.cwd(),directory=path.join(root,'.lab/cat-selector');
const registry=path.join(directory,'registry');await fs.mkdir(registry,{recursive:true});
const env={...process.env,PET_LAB_STATE_DIR:path.join(directory,'state'),PET_LAB_CLAUDE_REGISTRY:registry};
delete env.PET_LAB_PACK;
const cli=async(...args)=>(await execute(process.execPath,['bin/pet-lab.mjs',...args],{cwd:root,env,timeout:25000})).stdout;
try {
  assert.equal(JSON.parse(await cli('pets','--json')).length,16);
  await cli('cat','03');let status=JSON.parse(await cli('status','--json'));
  assert.equal(status.pack,'cat-03-blue-eyed-white');const firstPid=status.pid;
  await assert.rejects(cli('cat','99'));
  assert.equal(JSON.parse(await cli('status','--json')).pid,firstPid);
  await cli('cat','15');status=JSON.parse(await cli('status','--json'));
  assert.equal(status.pack,'cat-15-sunshine-fluff');assert.notEqual(status.pid,firstPid);
  await cli('stop');await cli('start');status=JSON.parse(await cli('status','--json'));
  assert.equal(status.pack,'cat-15-sunshine-fluff');assert.equal(status.ready,true);
  await cli('pet','17');status=JSON.parse(await cli('status','--json'));
  assert.equal(status.pack,'shiba-17-black-tan');
  const report={passed:true,fixtureOnly:true,checks:{listsSixteen:true,selectsShiba:true,selectsCat:true,rejectsUnknownWithoutStopping:true,switchRestartsOwnMonitor:true,choiceSurvivesRestart:true}};
  await fs.writeFile('evidence/cat-selector-check.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
} finally {await cli('stop').catch(()=>{});}
