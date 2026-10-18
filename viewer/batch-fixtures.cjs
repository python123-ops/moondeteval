// Generate actual native CLI batch outputs for viewer integration checks.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {execFileSync} = require('node:child_process');

function createFixtures(){
  const root=path.resolve(__dirname,'..');
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'moondeteval-viewer-'));
  function cleanup(){
    const target=path.resolve(directory);
    if(path.dirname(target)!==path.resolve(os.tmpdir()) || !path.basename(target).startsWith('moondeteval-viewer-'))throw new Error('Unexpected fixture directory');
    fs.rmSync(target,{recursive:true,force:true});
  }
  try{
    execFileSync('moon',['build','cli','--target','native','--release'],{cwd:root,stdio:'pipe'});
    const executable=['cli.exe','cli'].map(name=>path.join(root,'_build/native/release/build/cli',name)).find(file=>fs.existsSync(file));
    if(!executable)throw new Error('Native CLI build did not produce an executable');
    const examples=path.join(root,'examples');
    for(const [type,truth,models] of [
      ['bbox','compare-ground-truth.json',[['baseline','compare-baseline.json'],['candidate','compare-candidate.json']]],
      ['segm','mask-ground-truth.json',[['baseline','mask-baseline.json'],['candidate','mask-candidate.json'],['polygon','polygon-detections.json']]],
    ]){
      const args=[path.join(examples,'batch_eval.py'),'--cli',executable,'--ground-truth',path.join(examples,truth),
        '--baseline','baseline','--iou-type',type,'--output-dir',path.join(directory,type),'--diagnostics','--image-ranking','--pr-curves'];
      for(const [name,file] of models)args.push('--model',name,path.join(examples,file));
      execFileSync(process.env.PYTHON || (process.platform==='win32'?'python':'python3'),args,{cwd:root,stdio:'pipe'});
    }
    const legacy=path.join(directory,'legacy');fs.mkdirSync(legacy);
    for(const name of fs.readdirSync(path.join(directory,'bbox')))fs.copyFileSync(path.join(directory,'bbox',name),path.join(legacy,name));
    const index=JSON.parse(fs.readFileSync(path.join(legacy,'index.json'),'utf8'));
    index.format_version='1';delete index.iou_type;index.models.forEach(model=>delete model.iou_type);
    fs.writeFileSync(path.join(legacy,'index.json'),JSON.stringify(index));
    return {directory,bbox:path.join(directory,'bbox'),segm:path.join(directory,'segm'),legacy,
      cleanup};
  }catch(error){cleanup();throw error;}
}
module.exports={createFixtures};
