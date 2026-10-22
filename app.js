(() => {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const state = { sb:null, user:null, groups:[], group:null, orgs:[], org:null, role:null, isSystemAdmin:false, people:[], cycle:[], cycleIndex:0, currentPerson:null, editingPhotoPath:null, pendingPhoto:null };
  const priorityLabels = {1:'最應該認識',2:'應該認識',3:'可以認識'};
  const config = window.P139_CONFIG || {};
  const localKey = (groupId) => 'P139-learning-'+groupId;

  function setNotice(message, show=true) { const el=$('setupNotice'); el.textContent=message||''; el.classList.toggle('hidden',!show); }
  function escapeHtml(value) { return String(value||'').replace(/[&<>"']/g,(c)=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function setLoading(button, loading, label) { if(!button)return;button.disabled=loading;if(loading){button.dataset.oldText=button.textContent;button.textContent=label||'處理中…';}else if(button.dataset.oldText){button.textContent=button.dataset.oldText;delete button.dataset.oldText;} }
  function requireClient() { if(!state.sb)throw new Error('尚未完成 Supabase 設定。請依 README 設定 config.js。'); }
  function rpc(name,args) { requireClient();return state.sb.rpc(name,args||{}); }
  function list(data) { return Array.isArray(data)?data:(data&&Array.isArray(data.items)?data.items:[]); }
  function getLearning(groupId) { try{return JSON.parse(localStorage.getItem(localKey(groupId))||'{}');}catch{return{};} }
  function saveLearning(groupId,data) { localStorage.setItem(localKey(groupId),JSON.stringify(data));renderPersonalStats(); }

  function init() {
    $('accountCenterLink').href=config.accountCenterUrl||'#';
    const valid=config.supabaseUrl&&config.supabaseAnonKey&&!config.supabaseUrl.includes('YOUR_PROJECT')&&!config.supabaseAnonKey.includes('YOUR_SUPABASE');
    bindUi();
    if(!valid||!window.supabase){setNotice('目前是設定範本。完成 README 的 Supabase 設定與資料庫安裝後，才可載入群組。');return;}
    state.sb=window.supabase.createClient(config.supabaseUrl,config.supabaseAnonKey,{auth:{storageKey:'P139-auth',persistSession:false,autoRefreshToken:true,detectSessionInUrl:true}});
    loadPublicGroups();
  }

  function bindUi() {
    $('showAdminLogin').addEventListener('click',()=>{$('adminLoginFormWrap').classList.toggle('hidden');$('emailInput').focus();});
    $('togglePassword').addEventListener('click',()=>{const input=$('passwordInput');const visible=input.type==='password';input.type=visible?'text':'password';$('togglePassword').textContent=visible?'隱藏':'顯示';});
    $('loginForm').addEventListener('submit',login);$('logoutButton').addEventListener('click',logout);
    $('orgSelect').addEventListener('change',()=>{state.org=state.orgs.find(x=>x.id===$('orgSelect').value)||null;loadAdminPeople();});
    $('publicGroupSelect').addEventListener('change',async()=>{state.group=state.groups.find(g=>g.id===$('publicGroupSelect').value)||null;state.people=[];clearQuiz();if(state.group)await loadPublicPeople();renderPersonalStats();});
    $('startPractice').addEventListener('click',startPractice);$('answerForm').addEventListener('submit',submitAnswer);$('nextQuestion').addEventListener('click',nextQuestion);
    $('clearPersonalData').addEventListener('click',clearPersonalData);$('migrateLegacyPhotos').addEventListener('click',migrateLegacyPhotos);$('personPhoto').addEventListener('change',previewPhoto);$('personForm').addEventListener('submit',savePerson);$('cancelPersonEdit').addEventListener('click',resetPersonForm);$('groupForm').addEventListener('submit',createGroup);
  }

  async function loadPublicGroups() {
    setNotice('正在載入公開練習群組…');
    const {data,error}=await rpc('p139_public_list_groups');
    if(error){const code=error.code?' ['+error.code+']':'';const detail=error.message||'未知 Supabase 錯誤';const needsSql=['PGRST202','42883'].includes(error.code);setNotice((needsSql?'資料庫尚未更新：請依 README 重新執行 01、02、90 三份 P139 SQL。':'無法載入群組：')+detail+code);return;}
    state.groups=list(data);const select=$('publicGroupSelect');
    select.innerHTML=state.groups.map(g=>'<option value="'+escapeHtml(g.id)+'">'+escapeHtml(g.name)+'</option>').join('');
    if(!state.groups.length){select.innerHTML='<option value="">目前沒有可練習的群組</option>';setNotice('目前尚無已公開的人物名單，請由系統管理者建立群組並新增人物。');return;}
    state.group=state.groups[0];select.value=state.group.id;await loadPublicPeople();setNotice('',false);renderPersonalStats();
  }

  async function loadPublicPeople() {
    if(!state.group)return;
    const {data,error}=await rpc('p139_public_list_people',{p_org_id:state.group.id});
    if(error){setNotice('無法載入人物名單。');return;}
    state.people=list(data);
  }

  function photoUrl(path) { if(!path||!state.sb)return '';return state.sb.storage.from('p139-public').getPublicUrl(path).data.publicUrl; }

  function clearQuiz() { state.cycle=[];state.cycleIndex=0;state.currentPerson=null;$('quizCard').classList.add('hidden');$('emptyPractice').classList.remove('hidden'); }
  async function startPractice() {
    if(!state.group){setNotice('請先選擇群組。');return;}
    if(!state.people.length){await loadPublicPeople();}
    const priority=Number($('practicePriority').value);
    state.cycle=state.people.filter(p=>Number(p.recognition_priority)===priority).map(p=>({person_id:p.id,photo_path:p.photo_path}));
    for(let i=state.cycle.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[state.cycle[i],state.cycle[j]]=[state.cycle[j],state.cycle[i]];}
    state.cycleIndex=0;
    if(!state.cycle.length){setNotice('這個群組目前沒有此優先級的人物。');return;}
    setNotice('',false);$('emptyPractice').classList.add('hidden');$('quizCard').classList.remove('hidden');await showQuestion();
  }
  async function showQuestion() {
    if(!state.cycle.length)return;
    if(state.cycleIndex>=state.cycle.length){const last=state.cycle[state.cycle.length-1];state.cycle=state.people.filter(p=>Number(p.recognition_priority)===Number($('practicePriority').value)&&p.id!==last.person_id).map(p=>({person_id:p.id,photo_path:p.photo_path}));for(let i=state.cycle.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[state.cycle[i],state.cycle[j]]=[state.cycle[j],state.cycle[i]];}if(last&&state.people.filter(p=>Number(p.recognition_priority)===Number($('practicePriority').value)).length>1)state.cycle.push(last);else if(last)state.cycle=[last];state.cycleIndex=0;}
    state.currentPerson=state.cycle[state.cycleIndex];$('questionCounter').textContent='本輪 '+(state.cycleIndex+1)+' / '+state.cycle.length;
    $('answerInput').value='';$('answerInput').disabled=false;$('answerFeedback').className='feedback hidden';$('answerFeedback').textContent='';$('nextQuestion').classList.add('hidden');
    const img=$('quizPhoto');img.style.display='none';$('photoPlaceholder').classList.remove('hidden');$('photoPlaceholder').textContent='照片載入中';img.onload=()=>{img.style.display='block';$('photoPlaceholder').classList.add('hidden');};img.onerror=()=>{$('photoPlaceholder').textContent='照片暫時無法載入';};img.src=photoUrl(state.currentPerson.photo_path);$('answerInput').focus();
  }
  async function submitAnswer(event) {
    event.preventDefault();if(!state.currentPerson||!state.group)return;const answer=$('answerInput').value.trim();if(!answer)return;
    const button=$('answerForm').querySelector('button');setLoading(button,true,'比對中…');$('answerInput').disabled=true;
    const {data,error}=await rpc('p139_public_check_answer',{p_person_id:state.currentPerson.person_id,p_answer:answer});setLoading(button,false);
    if(error){$('answerInput').disabled=false;$('answerFeedback').className='feedback incorrect';$('answerFeedback').textContent='比對失敗，請稍後再試。';return;}
    const result=Array.isArray(data)?data[0]:data;const learning=getLearning(state.group.id);const person=learning[state.currentPerson.person_id]||{attempts:0,correct:0,wrong:[]};person.attempts++;if(result.is_correct)person.correct++;else{person.wrong=[answer,...(person.wrong||[])].slice(0,5);}learning[state.currentPerson.person_id]=person;saveLearning(state.group.id,learning);
    const box=$('answerFeedback');box.className='feedback '+(result.is_correct?'correct':'incorrect');box.textContent=result.is_correct?'答對了！ '+result.correct_name:'這次沒有答對。正確姓名是「'+result.correct_name+'」。';
    if(!result.is_correct&&result.confused_with)box.textContent+=' 你輸入的答案是「'+result.confused_with+'」的姓名，這次把兩位人物混淆了。';
    if(!result.is_correct&&person.wrong.length>1){const prior=document.createElement('span');prior.className='past-errors';prior.textContent='你之前也曾輸入：'+person.wrong.slice(1).map(x=>'「'+x+'」').join('、')+'。';box.appendChild(prior);}
    $('nextQuestion').classList.remove('hidden');
  }
  async function nextQuestion(){state.cycleIndex++;await showQuestion();}
  function renderPersonalStats(){const root=$('personalStats');if(!state.group){root.textContent='選擇群組後開始練習。';return;}const data=getLearning(state.group.id);const entries=Object.values(data);const attempts=entries.reduce((n,x)=>n+(x.attempts||0),0);const correct=entries.reduce((n,x)=>n+(x.correct||0),0);root.textContent=attempts?`「${state.group.name}」已答 ${attempts} 題，答對 ${correct} 題；紀錄保存在本機。`:`「${state.group.name}」尚無練習紀錄。`;}
  function clearPersonalData(){if(state.group)localStorage.removeItem(localKey(state.group.id));renderPersonalStats();setNotice('已清除目前群組的本機練習紀錄。');}

  async function login(event){event.preventDefault();$('loginError').textContent='';if(!state.sb){$('loginError').textContent='請先完成 Supabase 設定。';return;}const button=$('loginForm').querySelector('button[type="submit"]');setLoading(button,true,'驗證中…');const {data,error}=await state.sb.auth.signInWithPassword({email:$('emailInput').value.trim(),password:$('passwordInput').value});setLoading(button,false);if(error){$('loginError').textContent='登入失敗，請確認管理者帳號密碼。';return;}state.user=data.user;await enterAdmin();}
  async function enterAdmin(){const {data,error}=await rpc('p139_list_my_organizations');if(error){$('loginError').textContent='無法確認管理權限。';await state.sb.auth.signOut({scope:'local'});return;}state.orgs=list(data);if(!state.orgs.length){$('loginError').textContent='此帳號沒有 P139 管理群組權限。';await state.sb.auth.signOut({scope:'local'});state.user=null;return;}const adminCheck=await rpc('p139_is_system_admin');state.isSystemAdmin=!adminCheck.error&&Boolean(adminCheck.data);$('adminPanel').classList.remove('hidden');$('adminLoginPanel').classList.add('hidden');$('userEmail').textContent=state.user.email||'';$('orgSelect').innerHTML=state.orgs.map(g=>'<option value="'+escapeHtml(g.id)+'">'+escapeHtml(g.name)+'</option>').join('');state.org=state.orgs[0];$('orgSelect').value=state.org.id;$('createGroupPanel').classList.toggle('hidden',!state.isSystemAdmin);await loadAdminPeople();}
  async function logout(){if(state.sb)await state.sb.auth.signOut({scope:'local'});state.user=null;state.orgs=[];state.org=null;state.isSystemAdmin=false;$('adminPanel').classList.add('hidden');$('adminLoginPanel').classList.remove('hidden');$('adminLoginFormWrap').classList.add('hidden');$('passwordInput').value='';$('loginError').textContent='';}
  async function createGroup(event){event.preventDefault();const button=$('groupForm').querySelector('button');setLoading(button,true,'建立中…');const {data,error}=await rpc('p139_create_group',{p_group_name:$('groupName').value.trim()});setLoading(button,false);if(error){setNotice('建立群組失敗：'+error.message);return;}$('groupForm').reset();const result=Array.isArray(data)?data[0]:data;await enterAdmin();if(result&&result.group_id){state.org=state.orgs.find(g=>g.id===result.group_id)||state.org;$('orgSelect').value=state.org.id;}await loadAdminPeople();await loadPublicGroups();setNotice('群組已建立。');}

  async function compressImage(file){if(!file||!file.type.startsWith('image/'))throw new Error('請選擇圖片檔。');const bitmap=await createImageBitmap(file,{imageOrientation:'from-image'});let scale=Math.min(1,1200/Math.max(bitmap.width,bitmap.height)),width=Math.round(bitmap.width*scale),height=Math.round(bitmap.height*scale),quality=.86,blob=null;for(let i=0;i<18;i++){const canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;const ctx=canvas.getContext('2d',{alpha:false});ctx.fillStyle='#fff';ctx.fillRect(0,0,width,height);ctx.drawImage(bitmap,0,0,width,height);blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',quality));if(blob&&blob.size<=102400)break;if(quality>.48)quality-=.07;else{width=Math.max(320,Math.round(width*.86));height=Math.max(320,Math.round(height*.86));quality=.76;}}bitmap.close();if(!blob)throw new Error('照片壓縮失敗。');return new File([blob],'portrait.jpg',{type:'image/jpeg',lastModified:Date.now()});}
  async function previewPhoto(){const file=$('personPhoto').files&&$('personPhoto').files[0];if(!file)return;$('compressionStatus').textContent='正在壓縮照片…';$('photoPreviewWrap').classList.remove('hidden');try{state.pendingPhoto=await compressImage(file);$('photoPreview').src=URL.createObjectURL(state.pendingPhoto);$('compressionStatus').textContent='已壓縮至 '+Math.round(state.pendingPhoto.size/1024)+' KB。';}catch(e){state.pendingPhoto=null;$('compressionStatus').textContent=e.message;}}
  async function uploadPhoto(file,path){const {error}=await state.sb.storage.from('p139-public').upload(path,file,{contentType:'image/jpeg',upsert:true,cacheControl:'3600'});if(error)throw new Error('照片上傳失敗：'+error.message);return path;}
  async function savePerson(event){event.preventDefault();if(!state.user||!state.org)return;const id=$('personId').value||crypto.randomUUID(),name=$('personName').value.trim(),aliases=$('personAliases').value.split(/[\n,，]/).map(x=>x.trim()).filter(Boolean);let photoPath=state.editingPhotoPath||null;const button=$('savePerson');setLoading(button,true,'儲存中…');try{if(state.pendingPhoto){photoPath=state.org.id+'/'+id+'.jpg';await uploadPhoto(state.pendingPhoto,photoPath);}if(!photoPath)throw new Error('請上傳人物照片。');const {error}=await rpc('p139_save_person',{p_org_id:state.org.id,p_person_id:id,p_display_name:name,p_aliases:aliases,p_photo_path:photoPath,p_recognition_priority:Number($('personPriority').value)});if(error)throw new Error('人物資料儲存失敗：'+error.message);resetPersonForm();await loadAdminPeople();await loadPublicGroups();setNotice('人物資料已儲存。');}catch(e){setNotice(e.message);}finally{setLoading(button,false);}}
  function resetPersonForm(){$('personForm').reset();$('personId').value='';state.editingPhotoPath=null;state.pendingPhoto=null;$('photoPreviewWrap').classList.add('hidden');$('cancelPersonEdit').classList.add('hidden');$('savePerson').textContent='新增人物';}
  async function loadAdminPeople(){if(!state.user||!state.org)return;const root=$('adminPeople');root.innerHTML='<p class="muted">載入名單中…</p>';const {data,error}=await rpc('p139_list_people_for_admin',{p_org_id:state.org.id});if(error){root.textContent='無法載入人物名單。';return;}const rows=list(data);root.innerHTML='';rows.forEach(person=>{const row=document.createElement('div');row.className='admin-person';const img=document.createElement('img');img.src=photoUrl(person.photo_path);img.alt='';const name=document.createElement('div');name.className='person-name';name.innerHTML=escapeHtml(person.display_name)+'<div class="small-note">'+priorityLabels[person.recognition_priority]+' · '+(person.is_active?'使用中':'已停用')+(person.aliases&&person.aliases.length?' · 別名：'+escapeHtml(person.aliases.join('、')):'')+'</div>';const actions=document.createElement('div');actions.className='admin-actions';const edit=document.createElement('button');edit.className='button quiet';edit.type='button';edit.textContent='編輯';edit.addEventListener('click',()=>editPerson(person));const active=document.createElement('button');active.className='button secondary';active.type='button';active.textContent=person.is_active?'停用':'啟用';active.addEventListener('click',()=>togglePerson(person));actions.append(edit,active);row.append(img,name,actions);root.appendChild(row);});if(!rows.length)root.innerHTML='<p class="muted">此群組尚未建立人物資料。</p>';}
  function editPerson(person){$('personId').value=person.id;$('personName').value=person.display_name;$('personAliases').value=(person.aliases||[]).join('\n');$('personPriority').value=String(person.recognition_priority||2);state.editingPhotoPath=person.photo_path;state.pendingPhoto=null;$('photoPreviewWrap').classList.remove('hidden');$('compressionStatus').textContent='若不選新照片，將保留原照片。';$('photoPreview').src=photoUrl(person.photo_path);$('cancelPersonEdit').classList.remove('hidden');$('savePerson').textContent='儲存修改';$('personName').scrollIntoView({behavior:'smooth',block:'center'});}
  async function togglePerson(person){const {error}=await rpc('p139_set_person_active',{p_person_id:person.id,p_is_active:!person.is_active});if(error){setNotice('更新人物狀態失敗。');return;}await loadAdminPeople();await loadPublicGroups();}
  async function migrateLegacyPhotos(){
    if(!state.user||!state.org)return;
    const button=$('migrateLegacyPhotos');setLoading(button,true,'搬移中…');setNotice('正在檢查此群組的舊版照片…');
    const {data,error}=await rpc('p139_list_people_for_admin',{p_org_id:state.org.id});
    if(error){setNotice('無法讀取群組名單：'+(error.message||'未知錯誤'));setLoading(button,false);return;}
    const people=list(data);let moved=0,failed=0,notFound=0;
    for(const person of people){
      try{
        const oldPhoto=await state.sb.storage.from('p139-private').download(person.photo_path);
        if(oldPhoto.error){if(oldPhoto.error.statusCode==='404'||/not found|object not found/i.test(oldPhoto.error.message||'')){notFound++;continue;}throw oldPhoto.error;}
        const copied=await state.sb.storage.from('p139-public').upload(person.photo_path,oldPhoto.data,{contentType:'image/jpeg',upsert:true,cacheControl:'3600'});
        if(copied.error)throw copied.error;moved++;
      }catch(e){failed++;}
    }
    setLoading(button,false);
    if(moved){await loadAdminPeople();await loadPublicGroups();setNotice(`舊照片搬移完成：${moved} 張已複製到公開照片空間；${notFound} 張不在舊版私有空間；${failed} 張搬移失敗。原照片未刪除。`);}
    else if(!failed)setNotice(`沒有找到可搬移的舊版照片（${notFound} 張不在 p139-private）。若照片曾在 V0.2 或 V0.3 新增，它們應已在 p139-public，請檢查群組載入錯誤及 config.js 專案設定。`);
    else setNotice(`舊照片搬移失敗 ${failed} 張，未找到 ${notFound} 張。請確認已執行 V0.4 SQL、登入帳號具有該群組管理權，以及 Storage 的舊照片讀取權限。`);
  }

  init();
})();
