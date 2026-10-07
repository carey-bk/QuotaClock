'use strict';
// English remains the static, no-JavaScript fallback. Both languages live in one catalog.
(() => {
 const catalog=window.QuotaClockLocales;
 const normalize=value=>value.trim().replace(/\s+/g,' ');
 const exact=new Map(catalog.filter(row=>!row.en.includes('{')).map(row=>[normalize(row.en),row['zh-CN']]));
 const patterns=catalog.filter(row=>row.en.includes('{')).map(row=>{
  const names=[];
  const source=normalize(row.en).split(/(\{\w+\})/).map(part=>{
   if(/^\{\w+\}$/.test(part)){names.push(part.slice(1,-1));return '(.+?)';}
   return part.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
  }).join('');
  return {regex:new RegExp('^'+source+'$'),names,translation:row['zh-CN']};
 });
 let language='en';
 try{if(localStorage.getItem('quotaclock-language')==='zh-CN')language='zh-CN';}catch{}
 const records=new WeakMap();
 const attributes=['alt','aria-label','title','placeholder'];
 function translate(value){
  if(language==='en')return value;
  const key=normalize(value);let result=exact.get(key);
  if(result===undefined)for(const pattern of patterns){
   const match=key.match(pattern.regex);if(!match)continue;
   result=pattern.translation.replace(/\{(\w+)\}/g,(_,name)=>match[pattern.names.indexOf(name)+1]);break;
  }
  return result===undefined?value:result;
 }
 function update(node,key,value,write){
  let fields=records.get(node);if(!fields){fields=new Map();records.set(node,fields);}
  let record=fields.get(key);
  if(!record||value!==record.output)record={source:value};
  const output=translate(record.source);record.output=output;fields.set(key,record);
  if(output!==value)write(output);
 }
 function scan(root){
  if(root.nodeType===Node.TEXT_NODE){
   if(root.parentElement?.closest('script,style,[data-language-control]'))return;
   if(root.data.trim())update(root,'text',root.data,value=>root.data=value);
   return;
  }
  if(root.nodeType!==Node.ELEMENT_NODE)return;
  if(root.matches('script,style,[data-language-control]'))return;
  for(const key of attributes)if(root.hasAttribute(key))update(root,key,root.getAttribute(key),value=>root.setAttribute(key,value));
  if(root.matches('meta[name="description"],meta[property="og:title"],meta[property="og:description"],meta[property="og:image:alt"]'))update(root,'content',root.content,value=>root.content=value);
  for(const child of root.childNodes)scan(child);
 }
 const observer=new MutationObserver(changes=>{
  observer.disconnect();
  for(const change of changes){
   if(change.type==='childList')for(const node of change.addedNodes)scan(node);
   else scan(change.target);
  }
  observe();
 });
 function observe(){observer.observe(document.documentElement,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:attributes});}
 const controls=[...document.querySelectorAll('[data-language]')];
 function apply(next,persist=false){
  // Hold the current section at the same visual offset when translated line lengths change.
  const anchor=[...document.querySelectorAll('main>section')].find(section=>section.getBoundingClientRect().bottom>80);
  const offset=anchor?.getBoundingClientRect().top;
  observer.disconnect();language=next;document.documentElement.lang=language;
  scan(document.documentElement);
  controls.forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.language===language)));
  if(persist){try{localStorage.setItem('quotaclock-language',language);}catch{}}
  if(anchor&&persist){const delta=anchor.getBoundingClientRect().top-offset;window.scrollTo({top:scrollY+delta,behavior:'instant'});}
  observe();
 }
 controls.forEach(button=>button.addEventListener('click',()=>apply(button.dataset.language,true)));
 apply(language);
})();
