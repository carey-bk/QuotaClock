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

// Native artwork is captured from production SwiftUI views with fictional data.
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const asset = name => `assets/native/${name}.webp`;
let account = 'alpha';
const stage = document.querySelector('#native-switch-stage');
const chooser = document.querySelector('#native-chooser');
const openSwitcher = document.querySelector('#open-switcher');
const status = document.querySelector('#switch-status');
const play = document.querySelector('#play-switch');
const switchHint = document.querySelector('.native-switch-intro p');
let generation = 0;
let busy = false;
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
function syncNativeViews(next) {
 account = next;
 const name = next === 'alpha' ? 'Alpha' : 'Beta';
 const quota = next === 'alpha' ? 87 : 100;
 document.querySelectorAll('[data-native-saver]').forEach(node => {
  const url = asset(`saver-${node.dataset.nativeSaver}-${next}`);
  if(node.tagName === 'SOURCE') node.srcset = url;
  else { node.src = url; node.alt = `Native QuotaClock screen saver: Codex ${name} ${quota}% and secondary AI services. Illustrative data.`; }
 });
 document.querySelectorAll('[data-native-menu]').forEach(node => { node.src = asset(`menu-${next}-idle`); node.alt = `Native menu: Codex ${name} ${quota}%, Claude Code 63%, DeepSeek ¥5.30.`; });
 document.querySelectorAll('[data-native-widget]').forEach(node => { node.src = asset(`widget-${next}`); node.alt = `Native QuotaClock widget: Codex ${name}, ${quota}% remaining.`; });
 document.querySelectorAll('[data-active-account]').forEach(node => node.textContent = name);
 const menu = document.querySelector('#switch-native-menu');
 menu.src = asset(`menu-${next}-idle`); menu.alt = `Native menu: Codex ${name}, ${quota}% remaining. Claude Code and DeepSeek remain visible.`;
 document.querySelector('#chooser-image').src = asset(`chooser-${next}`);
 document.querySelectorAll('[data-select-account]').forEach(button => {
  const current = button.dataset.selectAccount === next;
  button.disabled = current;
  const label = button.dataset.selectAccount === 'alpha' ? 'Alpha' : 'Beta';
  button.setAttribute('aria-label',current ? `${label} is the current account` : `Switch to Codex ${label}`);
 });
}
function step(value) {
 document.querySelectorAll('[data-step]').forEach(node => value === node.dataset.step ? node.setAttribute('aria-current','step') : node.removeAttribute('aria-current'));
}
function closeChooser(restoreFocus = true) {
 chooser.hidden = true; openSwitcher.setAttribute('aria-expanded','false');
 switchHint.textContent = 'Click the switch icon\nin the native action bar.';
 if(restoreFocus) openSwitcher.focus({preventScroll:true});
}
function showChooser(focus = true) {
 if(busy) return;
 chooser.hidden = false; openSwitcher.setAttribute('aria-expanded','true'); stage.dataset.state = 'choosing'; step('choose');
 switchHint.textContent = 'Choose your next\nCodex account.';
 status.textContent = `Choose ${account === 'alpha' ? 'Beta' : 'Alpha'} in the native account switcher.`;
 if(focus) chooser.querySelector('[data-select-account]:not(:disabled)').focus({preventScroll:true});
}
async function selectAccount(next, automatic = false) {
 if(busy || next === account) return;
 const run = automatic ? generation : ++generation;
 busy = true; openSwitcher.disabled = true;
 chooser.querySelectorAll('button').forEach(button => button.disabled = true);
 stage.dataset.state = 'switching'; status.textContent = `Switching to Codex ${next === 'beta' ? 'Beta' : 'Alpha'}…`;
 await pause(reducedMotion.matches ? 120 : 650);
 if(run !== generation) return;
 closeChooser(false); syncNativeViews(next);
 document.querySelector('#close-switcher').disabled = false;
 stage.dataset.state = 'success'; step('success'); busy = false; openSwitcher.disabled = false;
 switchHint.textContent = `Switch complete.\n${next === 'beta' ? '100' : '87'}% remaining.`;
 status.textContent = `Codex ${next === 'beta' ? 'Beta' : 'Alpha'} is ready. ${next === 'beta' ? '100' : '87'}% remaining. Screen saver, menu and widget previews updated.`;
 play.textContent = 'Replay animation';
 if(!automatic) openSwitcher.focus({preventScroll:true});
}
function stopPlayback() { generation++; stage.classList.remove('is-playing'); play.textContent='Replay animation'; }
openSwitcher?.addEventListener('click',()=>{stopPlayback(); showChooser();});
document.querySelector('#close-switcher')?.addEventListener('click',()=>{stopPlayback(); closeChooser(); stage.dataset.state='idle'; step('open'); status.textContent='Switcher closed. Your demo account stays unchanged.';});
document.querySelectorAll('[data-select-account]').forEach(button => button.addEventListener('click',()=>{stage.classList.remove('is-playing'); selectAccount(button.dataset.selectAccount);}));
document.addEventListener('keydown',event=>{
 if(event.key==='Escape' && !chooser.hidden && !busy) {stopPlayback(); closeChooser(); stage.dataset.state='idle'; step('open'); status.textContent='Switcher closed. Your demo account stays unchanged.';}
 if(event.key==='Tab' && !chooser.hidden && !busy && chooser.contains(document.activeElement)) {
  const buttons=[...chooser.querySelectorAll('button:not(:disabled)')];
  if(event.shiftKey && document.activeElement===buttons[0]) {event.preventDefault();buttons.at(-1).focus();}
  else if(!event.shiftKey && document.activeElement===buttons.at(-1)) {event.preventDefault();buttons[0].focus();}
 }
});
function pointAt(button) {
 const box=button.getBoundingClientRect(), frame=stage.getBoundingClientRect();
 stage.style.setProperty('--pointer-x',`${box.left-frame.left+box.width*.6}px`);
 stage.style.setProperty('--pointer-y',`${box.top-frame.top+box.height*.55}px`);
}
play?.addEventListener('click', async()=>{
 if(busy) return;
 const run=++generation; closeChooser(false); syncNativeViews('alpha'); step('open'); stage.dataset.state='idle';
 stage.scrollIntoView({block:'start',behavior:reducedMotion.matches?'instant':'smooth'});
 stage.classList.add('is-playing'); play.textContent='Playing…';
 status.textContent='Opening the native Codex account switcher…';
 pointAt(openSwitcher); await pause(reducedMotion.matches ? 250 : 1000);
 if(run!==generation)return; showChooser(false);
 await pause(reducedMotion.matches ? 250 : 1000); if(run!==generation)return;
 pointAt(chooser.querySelector('[data-select-account="beta"]'));
 await pause(reducedMotion.matches ? 150 : 800); if(run!==generation)return;
 await selectAccount('beta',true); if(run!==generation)return;
 stage.classList.remove('is-playing');
});
reducedMotion.addEventListener('change',()=>{if(reducedMotion.matches)stage.classList.remove('is-playing');});
// Only change screenshots: settings in the installed app are never touched.
const settingsTabs=[...document.querySelectorAll('[data-tab]')];
const settingsCopy={general:'General: behavior, refresh interval, appearance and app logo.',services:'AI Services: two Codex accounts, Claude Code, DeepSeek, Hero provider and Auto Hero.',menubar:'Menu Bar: real preview, icon, dropdown position and visible services.',saver:'Screen Saver: native preview, maximum providers, clock, date and visible services.'};
function selectSettingsTab(tab) {
 settingsTabs.forEach(button=>{const selected=button===tab;button.setAttribute('aria-selected',String(selected));button.tabIndex=selected?0:-1;});
 const image=document.querySelector('#native-settings-image'); image.src=asset(`settings-${tab.dataset.tab}`);image.alt=`Actual QuotaClock ${settingsCopy[tab.dataset.tab]}`;
 document.querySelector('#settings-panel').setAttribute('aria-labelledby',tab.id);
 document.querySelector('#settings-caption').textContent=`Native ${tab.textContent} settings.`;
 tab.scrollIntoView({block:'nearest',inline:'nearest',behavior:'instant'});
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
// Preserve the full native window, with an optional readable detail view on phones.
document.querySelectorAll('[data-zoom-target]').forEach(button=>button.addEventListener('click',()=>{
 const view=document.getElementById(button.dataset.zoomTarget);const zoomed=view.classList.toggle('is-zoomed');
 button.setAttribute('aria-pressed',String(zoomed));button.textContent=zoomed?'Fit window':'Zoom screenshot';
 view.scrollLeft=zoomed?145:0;
}));
const quotaCopy={87:'Plenty of limit remains.',63:'Still looking good.',20:'Running low.'};
document.querySelectorAll('[data-quota-state]').forEach(button=>button.addEventListener('click',()=>{
 const value=Number(button.dataset.quotaState);document.querySelector('#immersive-number').textContent=value+'%';document.querySelector('#immersive-progress').style.setProperty('--value',value+'%');document.querySelector('#immersive-copy').textContent=quotaCopy[value];document.querySelectorAll('[data-quota-state]').forEach(node=>node.setAttribute('aria-pressed',String(node===button)));
}));
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
