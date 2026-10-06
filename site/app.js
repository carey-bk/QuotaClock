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
const switchMenuToggle=document.querySelector('#switch-menu-toggle');
const switchPanel=document.querySelector('#switch-menu-panel');
let generation = 0;
let busy = false;
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
// Animate clipped layers of the authentic capture, preserving every native pixel.
document.querySelectorAll('[data-native-menu]').forEach(original=>{
 const stack=document.createElement('div');stack.className='native-menu-stack';
 original.before(stack);stack.append(original);original.classList.add('menu-measure');
 for(let i=0;i<4;i++){
  const layer=original.cloneNode(true);layer.removeAttribute('id');layer.className=`menu-layer menu-layer-${i}`;
  layer.alt='';layer.setAttribute('aria-hidden','true');layer.dataset.nativeMenu='';stack.append(layer);
 }
});
function syncNativeViews(next) {
 account = next;
 const name = next === 'alpha' ? 'Alpha' : 'Beta';
 const quota = next === 'alpha' ? 87 : 100;
 document.querySelectorAll('[data-native-saver]').forEach(node => {
  const url = asset(`saver-${node.dataset.nativeSaver}-${next}`);
  if(node.tagName === 'SOURCE') node.srcset = url;
  else { node.src = url; node.alt = `Native QuotaClock screen saver: Codex ${name} ${quota}% and secondary AI services. Illustrative data.`; }
 });
 document.querySelectorAll('[data-native-menu]').forEach(node => { node.src = asset(`menu-${next}-idle`); if(!node.hasAttribute('aria-hidden')) node.alt = `Native menu: Codex ${name} ${quota}%, Claude Code 63%, DeepSeek ¥5.30.`; });
 document.querySelectorAll('[data-native-widget]').forEach(node => { node.src = asset(`widget-${node.dataset.nativeWidget === "large" ? "large-" : ""}${next}`); node.alt = `Native QuotaClock widget: Codex ${name}, ${quota}% remaining.`; });
 document.querySelectorAll('[data-native-status]').forEach(node => { node.src = asset(`status-${next}`); node.alt = `QuotaClock, ${quota}% remaining`; });
 document.querySelectorAll('[data-active-account],[data-codex-account]').forEach(node => node.textContent = name);
 document.querySelectorAll('[data-codex-avatar]').forEach(node => node.textContent = name[0]);
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
 switchHint.textContent = 'Your current Codex account.';
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
 closeChooser(false);
 stage.dataset.state = 'signing-out'; step('restart'); play.disabled=true; switchMenuToggle.disabled=true;
 status.textContent = `Signing out of Codex ${account === 'alpha' ? 'Alpha' : 'Beta'}…`;
 switchHint.textContent = 'Signing out of the current account…';
 document.querySelector('[data-logout-copy]').textContent='Signing out…';
 await pause(reducedMotion.matches ? 120 : 1400); if(run !== generation) return;
 stage.dataset.state='restarting'; switchHint.textContent='Restarting Codex…'; status.textContent='Restarting Codex with the selected account…';
 await pause(reducedMotion.matches ? 120 : 1800); if(run !== generation) return;
 syncNativeViews(next); document.querySelector('[data-logout-copy]').textContent='Log out';
 play.disabled=false; switchMenuToggle.disabled=false;
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
function setSwitchMenu(open) {
 switchPanel.hidden=!open; switchMenuToggle.setAttribute('aria-expanded',String(open));
 switchMenuToggle.setAttribute('aria-label',`${open?'Close':'Open'} switching menu preview`);
 if(!open) closeChooser(false);
}
switchMenuToggle.addEventListener('click',()=>{if(busy)return;stopPlayback();setSwitchMenu(switchPanel.hidden);});
stage.addEventListener('keydown',event=>{if(event.key==='Escape'&&chooser.hidden&&!busy){stopPlayback();setSwitchMenu(false);switchMenuToggle.focus({preventScroll:true});}});
async function playWalkthrough(automatic=false){
 if(busy) return;
 const run=++generation; closeChooser(false); syncNativeViews('alpha'); step('open'); stage.dataset.state='idle'; setSwitchMenu(false);
 if(!automatic) stage.scrollIntoView({block:'start',behavior:reducedMotion.matches?'instant':'smooth'});
 stage.classList.add('is-playing'); play.textContent='Playing…';
 status.textContent='Opening the QuotaClock menu…';
 pointAt(switchMenuToggle); await pause(reducedMotion.matches ? 120 : 1000);
 if(run!==generation)return; setSwitchMenu(true);
 await pause(reducedMotion.matches ? 120 : 750); if(run!==generation)return;
 pointAt(openSwitcher); await pause(reducedMotion.matches ? 120 : 850);
 if(run!==generation)return; showChooser(false);
 await pause(reducedMotion.matches ? 120 : 900); if(run!==generation)return;
 pointAt(chooser.querySelector('[data-select-account="beta"]'));
 await pause(reducedMotion.matches ? 120 : 850); if(run!==generation)return;
 stage.classList.remove('is-playing'); await selectAccount('beta',true);
}
play?.addEventListener('click',()=>playWalkthrough());
if('IntersectionObserver' in window){
 const switchObserver=new IntersectionObserver(entries=>{if(entries.some(entry=>entry.isIntersecting)){switchObserver.disconnect();if(generation===0&&!reducedMotion.matches)playWalkthrough(true);}},{threshold:.45});
 switchObserver.observe(stage);
}
reducedMotion.addEventListener('change',()=>{if(reducedMotion.matches)stage.classList.remove('is-playing');});
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

// The native menu image sits beneath a working desktop status button.
document.querySelectorAll('[data-menu-preview]').forEach(scene=>{
 const toggle=scene.querySelector('[data-menu-toggle]');
 const panel=scene.querySelector('.desktop-dropdown');
 const automatic=scene.hasAttribute('data-auto-open');
 const feedback=scene.querySelector('[data-menu-feedback]');
 let revision=0, played=false, interacted=false, running=false;
 function setOpen(open){
  toggle.setAttribute('aria-expanded',String(open));panel.hidden=!open;scene.classList.toggle('is-open',open);
  if(automatic) toggle.setAttribute('aria-label',`${open?'Close':'Open'} QuotaClock menu`);
 }
 function cancel(){revision++;running=false;scene.classList.remove('is-demonstrating','is-pointing','is-clicking');}
 function manual(open){interacted=true;cancel();setOpen(open);}
 async function demonstrate(){
  cancel();const run=revision;running=true;setOpen(false);panel.querySelector('img').loading='eager';if(feedback)feedback.textContent='';
  if(reducedMotion.matches){setOpen(true);played=true;running=false;return;}
  const buttonBox=toggle.getBoundingClientRect(), sceneBox=scene.getBoundingClientRect();
  scene.style.setProperty('--menu-pointer-x',`${buttonBox.left-sceneBox.left+buttonBox.width*.55}px`);
  scene.classList.add('is-demonstrating');
  await pause(150);if(run!==revision)return;scene.classList.add('is-pointing');
  await pause(850);if(run!==revision)return;scene.classList.add('is-clicking');
  await pause(180);if(run!==revision)return;setOpen(true);played=true;scene.classList.remove('is-clicking');
  await pause(500);if(run!==revision)return;cancel();
 }
 toggle.addEventListener('click',()=>manual(toggle.getAttribute('aria-expanded')!=='true'));
 scene.querySelector('[data-menu-close]')?.addEventListener('click',()=>{manual(false);toggle.focus({preventScroll:true});});
 scene.addEventListener('keydown',event=>{if(event.key==='Escape'){event.preventDefault();manual(false);toggle.focus({preventScroll:true});}});
 scene.addEventListener('click',event=>{if(!event.target.closest('.desktop-bar,.desktop-dropdown'))manual(false);});
 scene.querySelector('[data-menu-refresh]')?.addEventListener('click',async()=>{
  interacted=true;cancel();const run=revision;panel.classList.add('is-refreshing');feedback.textContent='Refreshing preview…';
  await pause(reducedMotion.matches?0:400);panel.classList.remove('is-refreshing');
  if(run===revision)feedback.textContent='Preview up to date.';
 });
 if(automatic){
  scene.closest('.surface-quick').querySelector('[data-menu-replay]').addEventListener('click',()=>{interacted=true;scene.scrollIntoView({block:'start',behavior:reducedMotion.matches?'instant':'smooth'});demonstrate();});
  if('IntersectionObserver' in window){
   const observer=new IntersectionObserver(entries=>{for(const entry of entries){
    if(entry.isIntersecting&&!played&&!interacted&&!running)demonstrate();
    else if(!entry.isIntersecting&&running&&!played&&!interacted){cancel();setOpen(false);}
   }},{threshold:.45});observer.observe(scene);
  }else setOpen(true);
  reducedMotion.addEventListener('change',()=>{if(reducedMotion.matches&&running){cancel();setOpen(true);played=true;}});
 }
});
