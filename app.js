(() => {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const state = { sb:null, user:null, orgs:[], org:null, role:null, people:[], cycle:[], cycleIndex:0, currentPerson:null, editingPhotoPath:null, pendingPhoto:null };
  const priorityLabels = {1:'最想熟悉',2:'正在熟悉',3:'之後再熟悉'};
  const config = window.P139_CONFIG || {};

  function setNotice(message, show) { const el=$('setupNotice'); el.textContent=message||''; el.classList.toggle('hidden',!show); }
  function escapeHtml(value) { return String(value||'').replace(/[&<>"']/g,(c)=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function setLoading(button, loading, label) { if(!button) return; button.disabled=loading; if(loading){button.dataset.oldText=button.textContent;button.textContent=label||'處理中…';} else if(button.dataset.oldText){button.textContent=button.dataset.oldText;delete button.dataset.oldText;} }
  function requireClient() { if(!state.sb) throw new Error('尚未完成 Supabase 設定。請依 README 複製 config-sample.js 為 config.js 並填入專案設定。'); }
  function rpc(name,args) { requireClient(); return state.sb.rpc(name,args||{}); }
  function isUuid(value) { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
  function normalizeRpcList(data) { if(Array.isArray(data)) return data; if(data && Array.isArray(data.items)) return data.items; return []; }

  function init() {
    $('accountCenterLink').href=config.accountCenterUrl||'#';
    const valid=config.supabaseUrl && config.supabaseAnonKey && !config.supabaseUrl.includes('YOUR_PROJECT') && !config.supabaseAnonKey.includes('YOUR_SUPABASE');
    if(!valid || !window.supabase){ setNotice('目前是設定範本。完成 README 的 Supabase 設定與資料庫安裝後，才可登入 P139。',true); bindUi(); return; }
    state.sb=window.supabase.createClient(config.supabaseUrl,config.supabaseAnonKey,{auth:{storageKey:'P139-auth',persistSession:false,autoRefreshToken:true,detectSessionInUrl:true}});
    bindUi();
    state.sb.auth.getSession().then(({data})=>{ if(data && data.session) state.user=data.session.user; if(state.user) afterLogin(); });
  }

  function bindUi() {
    $('togglePassword').addEventListener('click',()=>{const input=$('passwordInput');const visible=input.type==='password';input.type=visible?'text':'password';$('togglePassword').textContent=visible?'隱藏':'顯示';});
    $('loginForm').addEventListener('submit',login);
    $('logoutButton').addEventListener('click',logout);
    $('orgSelect').addEventListener('change',()=>{state.org=state.orgs.find(x=>x.id===$('orgSelect').value)||null;state.role=state.org&&state.org.role;refreshRoleTabs();clearQuiz();loadPriorityPeople();});
    document.querySelectorAll('.tab').forEach((tab)=>tab.addEventListener('click',()=>showView(tab.dataset.view)));
    $('startPractice').addEventListener('click',startPractice);
    $('answerForm').addEventListener('submit',submitAnswer);
    $('nextQuestion').addEventListener('click',nextQuestion);
    $('personPhoto').addEventListener('change',previewPhoto);
    $('personForm').addEventListener('submit',savePerson);
    $('cancelPersonEdit').addEventListener('click',resetPersonForm);
    $('memberForm').addEventListener('submit',addMember);
  }

  async function login(event) {
    event.preventDefault(); $('loginError').textContent='';
    if(!state.sb){ $('loginError').textContent='請先完成 Supabase 設定。'; return; }
    const button=$('loginForm').querySelector('button[type="submit"]');setLoading(button,true,'登入中…');
    const {data,error}=await state.sb.auth.signInWithPassword({email:$('emailInput').value.trim(),password:$('passwordInput').value});
    setLoading(button,false);
    if(error){$('loginError').textContent='登入失敗，請確認帳號密碼或聯絡 P130 帳號中心。';return;}
    state.user=data.user; await afterLogin();
  }

  async function logout() {
    if(state.sb) await state.sb.auth.signOut({scope:'local'});
    state.user=null;state.orgs=[];state.org=null;state.role=null;state.people=[];state.cycle=[];state.currentPerson=null;
    $('appPanel').classList.add('hidden');$('loginPanel').classList.remove('hidden');$('passwordInput').value='';$('loginError').textContent='';
  }

  async function afterLogin() {
    $('loginPanel').classList.add('hidden');$('appPanel').classList.remove('hidden');$('userEmail').textContent=state.user.email||'';
    setNotice('正在確認您獲授權的團體…',true);
    const {data,error}=await rpc('p139_list_my_organizations');
    if(error){setNotice('無法取得團體權限。請確認 P139 SQL 已安裝，或聯絡該團體管理者。',true);return;}
    state.orgs=normalizeRpcList(data);
    $('orgSelect').innerHTML=state.orgs.map((o)=>'<option value="'+escapeHtml(o.id)+'">'+escapeHtml(o.name)+'</option>').join('');
    if(!state.orgs.length){setNotice('目前帳號尚未加入任何 P139 團體。請請團體管理者以 P130 註冊 Email 將您加入。',true);return;}
    state.org=state.orgs[0];state.role=state.org.role;$('orgSelect').value=state.org.id;setNotice('',false);refreshRoleTabs();loadPriorityPeople();
  }

  function refreshRoleTabs() {
    const admin=state.role==='admin';$('manageTab').classList.toggle('hidden',!admin);$('membersTab').classList.toggle('hidden',!admin);
    if(!admin && (document.querySelector('.tab.active')||{}).dataset?.view==='manage') showView('practice');
  }

  function showView(view) {
    document.querySelectorAll('.tab').forEach((tab)=>tab.classList.toggle('active',tab.dataset.view===view));
    ['practice','priorities','manage','members'].forEach((name)=>$(name+'View').classList.toggle('hidden',name!==view));
    if(view==='priorities') loadPriorityPeople();
    if(view==='manage') loadAdminPeople();
  }

  async function loadPriorityPeople() {
    if(!state.org) return;
    $('priorityPeople').innerHTML='<p class="muted">載入人物資料中…</p>';$('priorityEmpty').classList.add('hidden');
    const {data,error}=await rpc('p139_list_people_for_priority',{p_org_id:state.org.id});
    if(error){$('priorityPeople').textContent='無法載入人物資料。';return;}
    state.people=normalizeRpcList(data);renderPriorityPeople();
  }

  async function signedPhoto(path) {
    if(!path||!state.sb) return '';
    const {data,error}=await state.sb.storage.from('p139-private').createSignedUrl(path,900);
    if(error||!data) return '';
    return data.signedUrl;
  }

  async function renderPriorityPeople() {
    const root=$('priorityPeople');root.innerHTML='';
    $('priorityEmpty').classList.toggle('hidden',state.people.length>0);
    state.people.forEach((person)=>{
      const card=document.createElement('article');card.className='person-tile';
      const img=document.createElement('img');img.alt='';img.src='';img.hidden=true;
      const initial=document.createElement('div');initial.className='person-initial';initial.textContent=(person.display_name||'?').slice(0,1);
      const copy=document.createElement('div');copy.innerHTML='<div class="person-name">'+escapeHtml(person.display_name)+'</div><div class="small-note">設定自己的練習優先級</div>';
      const select=document.createElement('select');select.className='priority-select';select.setAttribute('aria-label',person.display_name+' 的熟悉優先級');
      select.innerHTML='<option value="">尚未安排</option><option value="1">最想熟悉</option><option value="2">正在熟悉</option><option value="3">之後再熟悉</option>';
      if(person.priority)select.value=String(person.priority);
      select.addEventListener('change',()=>setPriority(person.id,select.value));
      card.append(img,initial,copy,select);root.appendChild(card);
      signedPhoto(person.photo_path).then((url)=>{if(url){img.src=url;img.hidden=false;initial.classList.add('hidden');}});
    });
  }

  async function setPriority(personId,value) {
    const priority=value?Number(value):null;
    const {error}=await rpc('p139_set_my_priority',{p_person_id:personId,p_priority:priority});
    if(error){setNotice('優先級儲存失敗，請稍後再試。',true);loadPriorityPeople();return;}
    const person=state.people.find(p=>p.id===personId);if(person)person.priority=priority;
  }

  function clearQuiz() { state.cycle=[];state.cycleIndex=0;state.currentPerson=null;$('quizCard').classList.add('hidden');$('emptyPractice').classList.remove('hidden'); }

  async function startPractice() {
    if(!state.org){setNotice('請先選擇已授權的團體。',true);return;}
    const priority=Number($('practicePriority').value);const button=$('startPractice');setLoading(button,true,'準備題目…');
    const {data,error}=await rpc('p139_get_quiz_cycle',{p_org_id:state.org.id,p_priority:priority,p_exclude_person_id:null});
    setLoading(button,false);
    if(error){setNotice('無法開始練習，請先設定個人優先級。',true);return;}
    state.cycle=normalizeRpcList(data);state.cycleIndex=0;
    if(!state.cycle.length){setNotice('這個優先級目前沒有安排人物。請先到「我的優先級」選擇人物。',true);return;}
    setNotice('',false);$('emptyPractice').classList.add('hidden');$('quizCard').classList.remove('hidden');await showQuestion();
  }

  async function showQuestion() {
    if(!state.cycle.length) return;
    if(state.cycleIndex>=state.cycle.length){
      const last=state.cycle[state.cycle.length-1].person_id;
      const {data,error}=await rpc('p139_get_quiz_cycle',{p_org_id:state.org.id,p_priority:Number($('practicePriority').value),p_exclude_person_id:last});
      if(error||!normalizeRpcList(data).length){state.cycleIndex=0;} else {state.cycle=normalizeRpcList(data);state.cycleIndex=0;}
    }
    state.currentPerson=state.cycle[state.cycleIndex];
    $('questionCounter').textContent='本輪 '+(state.cycleIndex+1)+' / '+state.cycle.length;
    $('answerInput').value='';$('answerInput').disabled=false;$('answerFeedback').className='feedback hidden';$('answerFeedback').textContent='';$('nextQuestion').classList.add('hidden');
    const img=$('quizPhoto');img.style.display='none';$('photoPlaceholder').classList.remove('hidden');$('photoPlaceholder').textContent='照片載入中';
    const url=await signedPhoto(state.currentPerson.photo_path);
    if(url){img.onload=()=>{img.style.display='block';$('photoPlaceholder').classList.add('hidden');};img.onerror=()=>{$('photoPlaceholder').textContent='照片暫時無法載入';};img.src=url;}
    else $('photoPlaceholder').textContent='照片暫時無法載入';
    $('answerInput').focus();
  }

  async function submitAnswer(event) {
    event.preventDefault();if(!state.currentPerson)return;
    const answer=$('answerInput').value.trim();if(!answer)return;
    const button=$('answerForm').querySelector('button');setLoading(button,true,'比對中…');$('answerInput').disabled=true;
    const {data,error}=await rpc('p139_submit_answer',{p_person_id:state.currentPerson.person_id,p_answer:answer});
    setLoading(button,false);
    if(error){$('answerInput').disabled=false;$('answerFeedback').className='feedback incorrect';$('answerFeedback').textContent='送出失敗，請確認登入狀態後再試。';return;}
    const result=Array.isArray(data)?data[0]:data;const box=$('answerFeedback');box.className='feedback '+(result.is_correct?'correct':'incorrect');
    box.textContent=result.is_correct?'答對了！ '+result.correct_name:'這次沒有答對。正確姓名是「'+result.correct_name+'」。';
    if(!result.is_correct && result.confused_with){box.textContent+=' 你輸入的答案是「'+result.confused_with+'」的姓名，這次把兩位人物混淆了。';}
    if(!result.is_correct && Array.isArray(result.previous_wrong_answers) && result.previous_wrong_answers.length){
      const prior=document.createElement('span');prior.className='past-errors';prior.textContent='你以前也答錯過：'+result.previous_wrong_answers.map((x)=>'「'+x+'」').join('、')+'。這是你自己的過往紀錄。';box.appendChild(prior);
    }
    $('nextQuestion').classList.remove('hidden');
  }

  async function nextQuestion() { state.cycleIndex++;await showQuestion(); }

  async function compressImage(file) {
    if(!file||!file.type.startsWith('image/'))throw new Error('請選擇圖片檔。');
    const bitmap=await createImageBitmap(file,{imageOrientation:'from-image'});
    let scale=Math.min(1,1200/Math.max(bitmap.width,bitmap.height));
    let width=Math.round(bitmap.width*scale),height=Math.round(bitmap.height*scale),quality=.86,blob=null;
    for(let attempt=0;attempt<18;attempt++){
      const canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;
      const context=canvas.getContext('2d',{alpha:false});context.fillStyle='#ffffff';context.fillRect(0,0,width,height);context.drawImage(bitmap,0,0,width,height);
      blob=await new Promise((resolve)=>canvas.toBlob(resolve,'image/jpeg',quality));
      if(blob&&blob.size<=102400)break;
      if(quality>.48)quality-=.07;else{width=Math.max(320,Math.round(width*.86));height=Math.max(320,Math.round(height*.86));quality=.76;}
      if(width<=320&&height<=320&&quality<=.48)break;
    }
    bitmap.close();if(!blob)throw new Error('照片壓縮失敗。');
    return new File([blob],'portrait.jpg',{type:'image/jpeg',lastModified:Date.now()});
  }

  async function previewPhoto() {
    const file=$('personPhoto').files&&$('personPhoto').files[0];if(!file)return;
    $('compressionStatus').textContent='正在縮小照片…';$('photoPreviewWrap').classList.remove('hidden');
    try{state.pendingPhoto=await compressImage(file);$('photoPreview').src=URL.createObjectURL(state.pendingPhoto);$('compressionStatus').textContent='已縮小至 '+Math.round(state.pendingPhoto.size/1024)+' KB（目標約 100 KB）。';}
    catch(error){state.pendingPhoto=null;$('compressionStatus').textContent=error.message;}
  }

  async function uploadPhoto(file,path) {
    const {error}=await state.sb.storage.from('p139-private').upload(path,file,{contentType:'image/jpeg',upsert:true,cacheControl:'3600'});
    if(error)throw new Error('照片上傳失敗：'+error.message);
    return path;
  }

  async function savePerson(event) {
    event.preventDefault();if(state.role!=='admin'||!state.org)return;
    const id=$('personId').value||crypto.randomUUID();const name=$('personName').value.trim();
    const aliases=$('personAliases').value.split(/[\n,，]/).map(x=>x.trim()).filter(Boolean);
    let photoPath=state.editingPhotoPath||null;const button=$('savePerson');setLoading(button,true,'儲存中…');
    try{
      if(state.pendingPhoto){photoPath=state.org.id+'/'+id+'.jpg';await uploadPhoto(state.pendingPhoto,photoPath);}
      if(!photoPath)throw new Error('請上傳人物照片。');
      const {error}=await rpc('p139_save_person',{p_org_id:state.org.id,p_person_id:id,p_display_name:name,p_aliases:aliases,p_photo_path:photoPath});
      if(error)throw new Error('人物資料儲存失敗：'+error.message);
      resetPersonForm();await loadAdminPeople();await loadPriorityPeople();setNotice('人物資料已儲存。',true);
    }catch(error){setNotice(error.message,true);}finally{setLoading(button,false);}
  }

  function resetPersonForm() {
    $('personForm').reset();$('personId').value='';state.editingPhotoPath=null;state.pendingPhoto=null;$('photoPreviewWrap').classList.add('hidden');$('cancelPersonEdit').classList.add('hidden');$('savePerson').textContent='新增人物';
  }

  async function loadAdminPeople() {
    if(state.role!=='admin'||!state.org)return;
    const root=$('adminPeople');root.innerHTML='<p class="muted">載入名單中…</p>';
    const {data,error}=await rpc('p139_list_people_for_admin',{p_org_id:state.org.id});
    if(error){root.textContent='無法載入人物名單。';return;}
    const rows=normalizeRpcList(data);root.innerHTML='';
    rows.forEach((person)=>{
      const row=document.createElement('div');row.className='admin-person';
      const img=document.createElement('img');img.alt='';img.hidden=true;const initial=document.createElement('div');initial.className='person-initial';initial.textContent=(person.display_name||'?').slice(0,1);
      const name=document.createElement('div');name.className='person-name';name.innerHTML=escapeHtml(person.display_name)+'<div class="small-note">'+(person.is_active?'使用中':'已停用')+(person.aliases&&person.aliases.length?' · 別名：'+escapeHtml(person.aliases.join('、')):'')+'</div>';
      const actions=document.createElement('div');actions.className='admin-actions';const edit=document.createElement('button');edit.className='button quiet';edit.type='button';edit.textContent='編輯';edit.addEventListener('click',()=>editPerson(person));
      const active=document.createElement('button');active.className='button secondary';active.type='button';active.textContent=person.is_active?'停用':'啟用';active.addEventListener('click',()=>togglePerson(person));actions.append(edit,active);row.append(img,initial,name,actions);root.appendChild(row);
      signedPhoto(person.photo_path).then((url)=>{if(url){img.src=url;img.hidden=false;initial.classList.add('hidden');}});
    });
    if(!rows.length)root.innerHTML='<p class="muted">尚未建立人物資料。</p>';
  }

  function editPerson(person) {
    $('personId').value=person.id;$('personName').value=person.display_name;$('personAliases').value=(person.aliases||[]).join('\n');state.editingPhotoPath=person.photo_path;state.pendingPhoto=null;
    $('photoPreviewWrap').classList.remove('hidden');$('compressionStatus').textContent='若不選新照片，將保留原照片。';signedPhoto(person.photo_path).then((url)=>{if(url)$('photoPreview').src=url;});
    $('cancelPersonEdit').classList.remove('hidden');$('savePerson').textContent='儲存修改';$('personName').scrollIntoView({behavior:'smooth',block:'center'});
  }

  async function togglePerson(person) {
    const {error}=await rpc('p139_set_person_active',{p_person_id:person.id,p_is_active:!person.is_active});
    if(error){setNotice('更新人物狀態失敗。',true);return;}await loadAdminPeople();await loadPriorityPeople();
  }

  async function addMember(event) {
    event.preventDefault();if(state.role!=='admin'||!state.org)return;
    const {error}=await rpc('p139_add_member',{p_org_id:state.org.id,p_email:$('memberEmail').value.trim(),p_role:$('memberRole').value});
    $('memberFeedback').textContent=error?'加入失敗。請確認 Email 已在 P130 註冊，或您具有管理權限。':'已加入團體。';if(!error)$('memberForm').reset();
  }

  init();
})();
