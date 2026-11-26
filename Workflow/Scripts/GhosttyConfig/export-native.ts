import {plugin} from 'bun';
import {resolve} from 'node:path';
plugin({name:'native-data',setup(build){
 build.onResolve({filter:/^\$lib\//}, args=>({path:resolve(import.meta.dir,'src/lib',args.path.slice(5) + (/\.(png|svg|webp)$/.test(args.path) ? '' : '.ts'))}));
 build.onResolve({filter:/^\$app\/environment$/},()=>({path:'environment',namespace:'stub'}));
 build.onLoad({filter:/.*/,namespace:'stub'},()=>({contents:'export const dev = false;',loader:'js'}));
 build.onLoad({filter:/\.(png|svg|webp)$/},args=>({contents:`export default ${JSON.stringify(args.path.split('/').pop())}`,loader:'js'}));
}});
const {registry} = await import('./src/lib/settings/registry');
const {navigation} = await import('./src/lib/settings/navigation');
const {themes} = await import('./src/lib/data/themes');
registry.quitAfterLastWindowClosed.default='false';
// SVG option thumbnails are rendered natively from theme colors instead.
for(const entry of Object.values(registry)) for(const option of (entry.widget?.options ?? [])) if(typeof option==='object' && option.icon?.startsWith('data:')) delete option.icon;
console.log(JSON.stringify({revision:'fa7489fdb50015571d15375c2a3806f2ba1f6bf3',registry,navigation,themes},null,2));
