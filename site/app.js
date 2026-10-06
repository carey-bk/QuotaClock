'use strict';
const navToggle = document.querySelector('.nav-toggle');
const navigation = document.querySelector('#navigation');
function closeNavigation(){navigation?.classList.remove('open');navToggle?.setAttribute('aria-expanded','false');navToggle?.setAttribute('aria-label','Open navigation');}
navToggle?.addEventListener('click',()=>{const open=navToggle.getAttribute('aria-expanded')!=='true';navigation.classList.toggle('open',open);navToggle.setAttribute('aria-expanded',String(open));navToggle.setAttribute('aria-label',open?'Close navigation':'Open navigation');});
navigation?.addEventListener('click',event=>{if(event.target.closest('a'))closeNavigation();});
document.addEventListener('keydown',event=>{if(event.key==='Escape'&&navToggle?.getAttribute('aria-expanded')==='true'){closeNavigation();navToggle.focus();}});
const header=document.querySelector('.site-header');
addEventListener('scroll',()=>header?.classList.toggle('scrolled',scrollY>8),{passive:true});
const releaseDialog=document.querySelector('#release-dialog');
document.querySelectorAll('[data-release-info]').forEach(button=>button.addEventListener('click',()=>releaseDialog.showModal()));
document.querySelectorAll('.dialog-close,.dialog-done').forEach(button=>button.addEventListener('click',()=>releaseDialog.close()));

// All account values are public demo fixtures. Only the clock is live.
function updateClock(){
  const now=new Date();
  document.querySelectorAll('[data-clock]').forEach(clock=>{clock.textContent=new Intl.DateTimeFormat('en',{hour:'2-digit',minute:'2-digit',hour12:false}).format(now);clock.dateTime=now.toISOString();});
  document.querySelectorAll('[data-date]').forEach(date=>date.textContent=new Intl.DateTimeFormat('en',{weekday:'long',month:'short',day:'numeric'}).format(now));
}
updateClock();
setInterval(()=>{if(!document.hidden)updateClock();},1000);

const quotaToggle=document.querySelector('#quota-toggle');
const quotaDropdown=document.querySelector('#quota-dropdown');
function toggleQuota(open){if(!quotaToggle)return;quotaToggle.setAttribute('aria-expanded',String(open));quotaDropdown.hidden=!open;}
quotaToggle?.addEventListener('click',()=>toggleQuota(quotaToggle.getAttribute('aria-expanded')!=='true'));
document.addEventListener('keydown',event=>{if(event.key==='Escape'&&(quotaDropdown?.contains(document.activeElement)||document.activeElement===quotaToggle)){toggleQuota(false);quotaToggle.focus();}});

const demoAccounts=Object.freeze([
  Object.freeze({name:'Alpha',percent:87,weekly:20}),
  Object.freeze({name:'Beta',percent:63,weekly:42}),
  Object.freeze({name:'Gamma',percent:100,weekly:84})
]);
let currentDemoAccount='Alpha';
const reducedMotion=matchMedia('(prefers-reduced-motion: reduce)');
reducedMotion.addEventListener('change',()=>{
  if(reducedMotion.matches)document.querySelectorAll('.changed').forEach(node=>node.classList.remove('changed'));
});
function renderAccount(name){
  const account=demoAccounts.find(item=>item.name===name);
  if(!account||name===currentDemoAccount)return;
  currentDemoAccount=name;
  document.querySelectorAll('[data-current-name]').forEach(node=>node.textContent=account.name);
  document.querySelectorAll('[data-current-percent],[data-menubar-percent]').forEach(node=>node.textContent=account.percent+'%');
  document.querySelectorAll('[data-current-weekly]').forEach(node=>node.textContent=account.weekly+'%');
  document.querySelectorAll('[data-current-progress]').forEach(node=>node.style.setProperty('--value',account.weekly+'%'));
  const others=demoAccounts.filter(item=>item.name!==name);
  const menuSecondary=document.querySelector('[data-menu-secondary]');
  if(menuSecondary){menuSecondary.querySelector('i').textContent=others[0].name;menuSecondary.querySelector('b').textContent=others[0].percent+'%';}
  document.querySelectorAll('[data-secondary]').forEach(card=>{
    const secondary=others[Number(card.dataset.secondary)];
    card.querySelector('[data-secondary-name]').textContent=secondary.name;
    card.querySelector('[data-secondary-percent]').textContent=secondary.percent+'%';
    card.querySelector('[data-secondary-progress]').style.setProperty('--value',secondary.percent+'%');
  });
  document.querySelectorAll('[data-switch]').forEach(button=>{
    const current=button.dataset.switch===name;
    button.setAttribute('aria-disabled',String(current));
    button.setAttribute('aria-label',current?name+' is the current account':'Switch to '+button.dataset.switch);
    button.textContent=current?'Current':'Switch';
    const row=button.closest('[data-switch-row]');
    row.classList.toggle('is-current',current);
    row.querySelector('[data-switch-note]').textContent=current?'Current account':'Ready when you are';
  });
  document.querySelectorAll('[data-account-note]').forEach(node=>node.textContent=node.dataset.accountNote===name?'Current account · Hero':'Plus');
  document.querySelectorAll('[data-account-marker]').forEach(node=>node.hidden=node.dataset.accountMarker!==name);
  document.querySelectorAll('.saver-scene').forEach(node=>node.setAttribute('aria-label',`QuotaClock screen saver preview: Codex ${name}, ${account.percent}% remaining. Illustrative data.`));
  document.querySelector('#switch-status').textContent=`Switched to ${name}. ${account.percent}% remaining. All website demos are now in sync.`;
  if(!reducedMotion.matches){
    document.querySelectorAll('[data-current-card],.switch-result-metric,.menu-quota-card').forEach(node=>{
      node.classList.remove('changed');
      requestAnimationFrame(()=>node.classList.add('changed'));
    });
  }
}
document.querySelectorAll('[data-switch]').forEach(button=>button.addEventListener('click',()=>renderAccount(button.dataset.switch)));
document.addEventListener('animationend',event=>{if(event.animationName==='account-change')event.target.classList.remove('changed');});

const quotaCopy={87:'Plenty of limit remains.',63:'Still looking good.',20:'Running low.'};
function showQuotaState(value){
 document.querySelector('#immersive-number').textContent=value+'%';
 document.querySelector('#immersive-progress').style.setProperty('--value',value+'%');
 document.querySelector('#immersive-copy').textContent=quotaCopy[value];
 document.querySelectorAll('[data-quota-state]').forEach(button=>button.setAttribute('aria-pressed',String(Number(button.dataset.quotaState)===value)));
}
document.querySelectorAll('[data-quota-state]').forEach(button=>button.addEventListener('click',()=>showQuotaState(Number(button.dataset.quotaState))));
const settingsTabs=[...document.querySelectorAll('[data-tab]')];
function selectSettingsTab(tab){
 settingsTabs.forEach(button=>{const selected=button===tab;button.setAttribute('aria-selected',String(selected));button.tabIndex=selected?0:-1;document.getElementById(button.getAttribute('aria-controls')).hidden=!selected;});
 if(matchMedia('(max-width:700px)').matches)tab.scrollIntoView({block:'nearest',inline:'nearest',behavior:'instant'});
}
settingsTabs.forEach((button,index)=>{
 button.addEventListener('click',()=>selectSettingsTab(button));
 button.addEventListener('keydown',event=>{
  let next=index;
  if(['ArrowRight','ArrowDown'].includes(event.key))next=(index+1)%settingsTabs.length;
  else if(['ArrowLeft','ArrowUp'].includes(event.key))next=(index-1+settingsTabs.length)%settingsTabs.length;
  else if(event.key==='Home')next=0;else if(event.key==='End')next=settingsTabs.length-1;else return;
  event.preventDefault();selectSettingsTab(settingsTabs[next]);settingsTabs[next].focus();
 });
});
const mobileSettings=matchMedia('(max-width:700px)');
function setTabOrientation(){document.querySelector('.settings-tabs')?.setAttribute('aria-orientation',mobileSettings.matches?'horizontal':'vertical');}
setTabOrientation();mobileSettings.addEventListener('change',setTabOrientation);
const settingsWindow=document.querySelector('.settings-window');
function applyPreviewAppearance(){
 const selected=document.querySelector('input[name=appearance]:checked')?.value;
 if(settingsWindow)settingsWindow.dataset.previewAppearance=selected==='system'?(matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light'):selected;
}
matchMedia('(prefers-color-scheme:dark)').addEventListener('change',applyPreviewAppearance);
settingsWindow?.addEventListener('change',event=>{
 const target=event.target;
 if(target.name==='appearance')applyPreviewAppearance();
 if(target.id==='icon-style')document.querySelector('#settings-app-icon').src=target.value==='illuminated'?'assets/app-icon-illuminated.png':'assets/app-icon.png';
 if(target.id==='auto-hero')document.querySelector('#hero-preference-note').textContent=target.checked?'Follow the current Codex account in the preview.':'Keep the custom order: Alpha, Beta, Gamma, Delta.';
 const menuIndicator=document.querySelector('#settings-menu-indicator');
 if(target.id==='menu-icon-style'){menuIndicator.querySelector('img').src=target.value==='provider'?'assets/codex.svg':'assets/gauge.svg';menuIndicator.querySelector('img').alt=target.value==='provider'?'Codex':'QuotaClock';}
 if(target.id==='menu-position'){menuIndicator.style.marginLeft=target.value==='left'?'0':'auto';menuIndicator.style.marginRight=target.value==='right'?'0':'auto';}
 if(target.id==='menu-percentage')menuIndicator.querySelector('[data-menubar-percent]').hidden=!target.checked;
 if(target.id==='show-clock')document.querySelector('.settings-saver-preview [data-clock]').hidden=!target.checked;
 if(target.id==='show-date')document.querySelector('.settings-saver-preview [data-date]').hidden=!target.checked;
 if(target.id==='max-providers')document.querySelectorAll('.settings-saver-preview [data-secondary]').forEach((card,index)=>card.hidden=index>=Number(target.value)-1);
 const label=target.labels?.[0]?.textContent.trim()||target.name;
 const value=target.type==='checkbox'?(target.checked?'on':'off'):target.value;
 document.querySelector('.settings-feedback').textContent=`Preview updated: ${label} ${value}. Your Mac’s settings stay unchanged.`;
});

// Optional public metadata is lazy and never a dependency of the page or downloads.
const sourceSection=document.querySelector('[data-repository]');
async function loadGitHubMetadata(){
 const repo=sourceSection?.dataset.repository;
 if(!repo)return;
 const controller=new AbortController();const timeout=setTimeout(()=>controller.abort(),4500);
 try{
  const response=await fetch(`https://api.github.com/repos/${repo}`,{signal:controller.signal,credentials:'omit',referrerPolicy:'no-referrer'});
  if(!response.ok)return;
  const data=await response.json();
  if(Number.isSafeInteger(data.stargazers_count)&&data.stargazers_count>0){const stars=document.querySelector('[data-stars]');stars.textContent=data.stargazers_count.toLocaleString()+' stars';stars.hidden=false;}
 }catch{/* Static repository/release links remain usable offline or when rate limited. */}
 finally{clearTimeout(timeout);}
}
if(sourceSection&&'IntersectionObserver' in window){const sourceObserver=new IntersectionObserver(entries=>{if(entries.some(entry=>entry.isIntersecting)){sourceObserver.disconnect();loadGitHubMetadata();}},{rootMargin:'150px'});sourceObserver.observe(sourceSection);}

const device=document.querySelector('.hero .macbook');
if(device&&matchMedia('(hover:hover) and (pointer:fine)').matches){
 device.addEventListener('pointermove',event=>{if(reducedMotion.matches)return;const rect=device.getBoundingClientRect();device.style.setProperty('--device-y',((event.clientX-rect.left)/rect.width-.5)*.75+'deg');device.style.setProperty('--device-x',((event.clientY-rect.top)/rect.height-.5)*-.5+'deg');});
 device.addEventListener('pointerleave',()=>{device.style.setProperty('--device-y','0deg');device.style.setProperty('--device-x','0deg');});
}
// Watch sections instead of reading layout on every scroll tick.
if('IntersectionObserver' in window){
 const sectionObserver=new IntersectionObserver(entries=>{
  const current=entries.filter(entry=>entry.isIntersecting).sort((a,b)=>b.intersectionRatio-a.intersectionRatio)[0];
  if(!current)return;
  document.querySelectorAll('#navigation a[href^="#"]').forEach(link=>{if(link.hash==='#'+current.target.id)link.setAttribute('aria-current','location');else link.removeAttribute('aria-current');});
 },{rootMargin:'-15% 0px -50% 0px',threshold:0});
 ['overview','screen-saver','menu-bar','accounts'].forEach(id=>{const section=document.getElementById(id);if(section)sectionObserver.observe(section);});
}
