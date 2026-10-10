(() => {
  'use strict';

  const studio = document.getElementById('capture-studio');
  const root = document.getElementById('scene-root');
  const dialogRoot = document.getElementById('dialog-root');
  const source = document.getElementById('source-document');
  const toastElement = document.getElementById('toast');
  const paths = {
    capture: '<path d="M8 4H4v4m12-4h4v4M4 16v4h4m12-4v4h-4M7 7h10v10H7z"/>',
    scroll: '<rect x="6" y="3" width="12" height="18" rx="2"/><path d="M9 7h6m-6 4h6m-3 3v4m-2-2 2 2 2-2"/>',
    window: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18M6 6.5h.1m2.5 0h.1"/>',
    text: '<path d="M5 4h14M12 4v16M8 20h8M5 4v4m14-4v4"/>',
    translate: '<path d="M3 5h12M9 3v2M5 8c1 4 4 6 8 8m0-11c-1 5-4 9-9 12m10 3 4-11 4 11m-6.5-4h5"/>',
    image: '<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1.5"/><path d="m3 17 6-6 4 4 3-3 5 5"/>',
    pin: '<path d="m8 3 9 0-1 6 3 4H6l3-4-1-6m4 10v8"/>',
    history: '<path d="M3 11a9 9 0 1 1 2 7M3 5v6h6m3-5v6l4 2"/>',
    search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
    arrow: '<path d="m4 20 16-16M7 4h13v13"/>',
    rect: '<rect x="4" y="5" width="16" height="14" rx="1"/>',
    ellipse: '<ellipse cx="12" cy="12" rx="8" ry="7"/>',
    pencil: '<path d="m4 16 12-12 4 4-12 12-5 1 1-5m9-9 4 4"/>',
    number: '<circle cx="12" cy="12" r="9"/><path d="m10 9 2-2v10m-2 0h4"/>',
    mask: '<rect x="4" y="5" width="16" height="14" rx="2"/><path d="M8 5v14m4-14v14m4-14v14M4 10h16M4 14h16"/>',
    crop: '<path d="M7 3v14h14M3 7h14v14"/>',
    select: '<path d="m5 3 13 10-6 1-3 6-4-17"/>',
    undo: '<path d="M4 4v6h6M4 10c5-8 16-4 16 3 0 5-6 8-10 5"/>',
    redo: '<path d="M20 4v6h-6m6 0C15 2 4 6 4 13c0 5 6 8 10 5"/>',
    copy: '<rect x="8" y="7" width="12" height="14" rx="2"/><path d="M15 7V3H4v14h4"/>',
    save: '<path d="M12 3v11m-4-4 4 4 4-4M4 15v6h16v-6"/>',
    close: '<path d="m6 6 12 12M6 18 18 6"/>',
    back: '<path d="m14 5-7 7 7 7"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    pause: '<path d="M8 5v14M16 5v14"/>',
    play: '<path d="m7 4 13 8-13 8V4"/>',
    more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    settings: '<path d="M4 6h16M4 12h16M4 18h16"/><circle cx="8" cy="6" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="10" cy="18" r="2"/>',
    expand: '<path d="M4 9V4h5m6 0h5v5M4 15v5h5m6 0h5v-5"/>',
    warn: '<path d="m12 3 10 18H2L12 3m0 6v5m0 3h.01"/>',
    lock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 4v3"/>',
    spark: '<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3"/>',
    opacity: '<path d="M12 3C9 7 5 11 5 15a7 7 0 0 0 14 0c0-4-4-8-7-12Z"/>',
  };
  const icon = name => `<svg viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.capture}</svg>`;
  const esc = value => String(value).replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
  const button = (action, name, symbol, extra = '') => `<button type="button" class="native-button ${extra}" data-action="${action}" aria-label="${name}" title="${name}">${symbol ? icon(symbol) : ''}<span class="button-word">${name}</span></button>`;
  const glyphButton = (action, name, symbol, extra = '') => `<button type="button" class="native-button icon-button ${extra}" data-action="${action}" aria-label="${name}" title="${name}">${icon(symbol)}</button>`;
  const traffic = '<div class="traffic-lights" aria-hidden="true"><i></i><i></i><i></i></div>';
  const sampleText = '发布检查清单\n\n本次发布聚焦截图与长截图体验。请先完成核心流程，再进行视觉和性能验收。\n\n01 关键路径\n区域截图、滚动长截图、标注和复制。\n\n02 验收标准\n固定页头只保留一次，正文不重复、不遗漏。\n\n03 下一步\n确认长图中文字清晰，并检查暂停后的继续捕获。';
  const sampleEnglish = 'Release checklist\n\nThis release focuses on screenshots and scrolling capture. Complete the core workflow before reviewing visual quality and performance.\n\nKeep the fixed header only once. Do not duplicate or omit content.\n\nMake sure text stays readable in long captures and capture can resume after a pause.';
  const captions = {
    launcher:['入口','同一组命令，通过搜索、别名与快捷键进入'],
    selection:['选择区域','选区先确认，后续操作沿用同一张图片'],
    scroll:['长截图','手动滚动 → 检查接缝 → 统一编辑'],
    editor:['统一编辑器','普通截图和长截图共用标注与输出'],
    pin:['贴图','失焦保留，移动和缩放不改变原图'],
    ocr:['取字与翻译','在同一面板校正原文、翻译和复制；切换应用后保留'],
    translation:['截图翻译','复用现有引擎；截图来源不提供回填'],
    history:['截图历史','平面结果和可编辑原稿清楚区分'],
    settings:['Capture 设置','输出、长截图、历史与快捷键集中配置'],
    done:['操作完成','关闭临时窗口，返回原来的工作'],
  };
  const commands = [
    ['capture','Capture Screenshot','截图 · 区域 / 窗口','capture'],
    ['scroll','Capture Scrolling Screenshot','长截图 · 纵向 / 横向','scroll'],
    ['full','Capture Full Screen','当前屏幕截图','window'],
    ['ocr','Capture Text','截图取字 · OCR','text'],
    ['translate','Capture & Translate','截图翻译','translate'],
    ['edit','Edit Clipboard Image','编辑剪贴板图片','image'],
    ['pin','Pin Clipboard Image','贴出剪贴板图片','pin'],
    ['history','Screenshot History','截图历史','history'],
  ];
  const S = {
    scene:'scroll', intent:'scroll', axis:'vertical', phase:'running', auto:false, length:2840, frames:3,
    permission:true, enabled:true, selectionWindow:false, selection:null, lastWasLong:true,
    tool:'select', color:'#d45449', annotations:[], redo:[], selected:null, dirty:true, zoom:1,
    copyClose:true, retainRaw:false, cursor:false, format:'PNG', pinOpacity:100,
    query:'', selectedCommand:1, ocr:sampleText, ocrNotice:'', translated:false, showTranslation:false, engine:'Apple',
    dialog:null, failure:'none', generation:0, textPosition:null,
    history:[
      {name:'发布检查清单',dimension:'1600 × 4820',time:'10:18',editable:false,long:true,annotations:[]},
      {name:'方案评审 · 标注版',dimension:'1440 × 960',time:'09:42',editable:true,long:false,annotations:[{id:900,tool:'rect',x:53,y:160,w:350,h:75,color:'#d45449'}]},
      {name:'接口说明',dimension:'1600 × 3180',time:'昨天',editable:false,long:true,annotations:[]},
    ],
  };
  let autoTimer = null;
  let toastTimer = null;
  let nextAnnotation = 1;
  let pointer = null;
  let lastWheel = 0;
  let scope = new AbortController();

  function documentContent(extra = '') {
    const tasks = ['检查区域选择与窗口捕获','完成纵向和横向长截图','验证固定页头不重复','检查箭头、文字和遮盖','核对复制结果与保存结果'];
    return `<article class="document-content ${extra}"><div class="document-breadcrumb">工作笔记 / 产品发布</div><h1>发布检查清单</h1><p class="document-lead">把细节做好，再交到用户手中。</p><div class="document-labels"><span>进行中</span><span>Capture · Phase 1</span></div><div class="document-meta"><span class="document-avatar">林</span><span>设计与工程 · 9 月 23 日更新</span></div><h2>01　关键路径</h2><p>让截图、长截图和标注成为一个自然的连续操作。用户完成捕获后，可以检查内容、添加说明，再复制到正在进行的工作中。</p><div class="document-note">长截图应保留完整正文。固定页头只出现一次，停止时保留已经捕获的内容。</div><h2>02　发布前检查</h2>${tasks.map((t,i)=>`<div class="document-task"><i class="${i<2?'checked':''}"></i><span>${t}</span></div>`).join('')}<h2>03　验证记录</h2><table class="document-table"><thead><tr><th>场景</th><th>关注点</th><th>负责人</th></tr></thead><tbody><tr><td>文档长截图</td><td>不重复、不漏行</td><td>工程</td></tr><tr><td>暂停后继续</td><td>重新连接已有内容</td><td>工程</td></tr><tr><td>小字号文字</td><td>清晰且可识别</td><td>设计</td></tr><tr><td>Light / Dark</td><td>控件清楚、内容原色</td><td>设计</td></tr></tbody></table><h2>04　下一步</h2><p>检查完整输出，确认细小文字和表格边缘清晰。切换到原应用继续工作后，贴图仍然可见。</p><div class="document-task"><i></i><span>记录峰值内存与关闭后的回落</span></div><div class="document-task"><i></i><span>在外接显示器上完成一次完整操作</span></div><h2>05　交付</h2><p>以同一套样本对照原始内容和最终图片，完成交互、视觉与性能验收。</p></article>`;
  }

  function stopAuto() { clearInterval(autoTimer); autoTimer=null; S.auto=false; }
  function notify(message, error=false) {
    clearTimeout(toastTimer);
    toastElement.className=`toast${error?' error':''}`;
    toastElement.innerHTML=`${esc(message)}${icon(error?'warn':'check')}`;
    toastElement.hidden=false;
    toastTimer=setTimeout(()=>{toastElement.hidden=true;},2500);
  }
  function switchScene(scene, review=false) {
    if (scene !== 'scroll') stopAuto();
    S.generation++;
    S.dialog=null; S.textPosition=null; S.selected=null;
    if (review) {
      S.failure='none'; document.getElementById('failure-scenario').value='none';
      if (scene==='selection') {S.intent='capture';S.selectionWindow=false;S.selection=null;}
      if (scene==='scroll') {stopAuto();S.phase='running';S.length=2840;S.frames=3;S.lastWasLong=true;}
      if (scene==='editor') {S.lastWasLong=true;S.dirty=true;}
      if (scene==='ocr') {S.ocr=sampleText;S.ocrNotice='';S.showTranslation=false;}
    }
    S.scene=scene;
    render();
  }
  function commandRows() {
    const q=S.query.trim().toLowerCase();
    return commands.filter(c=>`${c[1]} ${c[2]}`.toLowerCase().includes(q));
  }
  function launcherMarkup() {
    const filtered=commandRows(); S.selectedCommand=Math.max(0,Math.min(S.selectedCommand,filtered.length-1));
    return `<div class="launcher surface"><div class="launcher-search">${icon('search')}<input id="command-search" aria-label="搜索截图命令" placeholder="搜索截图、长截图、取字…" value="${esc(S.query)}" autocomplete="off"></div><div class="section-label"><span>CAPTURE</span><span>原生截图工作流</span></div><div class="command-list" id="command-list">${filtered.map((c,i)=>`<button type="button" class="command-row ${i===S.selectedCommand?'selected':''}" data-command="${c[0]}"><span class="command-icon">${icon(c[3])}</span><span class="command-label"><span>${c[1]}</span><small>${c[2]}</small></span><span class="command-kind">Command</span></button>`).join('')||'<div class="empty-state">没有找到命令</div>'}</div><div class="palette-footer"><span>Tinycast</span><div class="glass">${button('run-selected','打开','play')}</div></div></div>`;
  }
  function selectionMarkup() {
    const selectedStyle=S.selection?`style="left:${S.selection.x}px;top:${S.selection.y}px;width:${S.selection.w}px;height:${S.selection.h}px"`:'';
    const dim=S.selection?`${Math.round(S.selection.w*2)} × ${Math.round(S.selection.h*2)} px`:'1600 × 960 px';
    return `<div class="selection-scrim"></div><div class="selection-help">拖动调整选区 · Space 切换窗口 · Escape 取消</div><div class="selection-frame drag-enabled ${S.selectionWindow?'window-mode':''}" id="selection-frame" ${selectedStyle} role="img" aria-label="截图选择区域"><i class="selection-handle"></i><i class="selection-handle"></i><span class="dimension-label">${S.selectionWindow?'窗口 · 工作笔记':dim}</span></div><div class="selection-toolbar glass">${button('selection-mode',S.selectionWindow?'区域选择':'窗口选择','window')}${S.intent==='scroll'?`<select id="capture-axis" class="native-select" aria-label="滚动方向"><option value="vertical" ${S.axis==='vertical'?'selected':''}>纵向</option><option value="horizontal" ${S.axis==='horizontal'?'selected':''}>横向</option></select>`:button('selection-scroll','长截图','scroll')}${S.intent==='capture'?button('edit-selection','编辑','pencil'):''}${button('confirm-selection',S.intent==='scroll'?'开始捕获':S.intent==='ocr'?'识别文字':S.intent==='translate'?'识别并翻译':'复制',S.intent==='scroll'?'play':S.intent==='capture'?'copy':'check','primary pill')}${glyphButton('cancel-selection','取消截图','close')}</div>`;
  }
  function scrollMarkup() {
    const paused=S.phase==='paused'; const failed=['failed','target'].includes(S.phase);
    const title=failed?'已暂停':paused?'已暂停':S.auto?'正在自动滚动':'正在捕获';
    const lengthText=S.axis==='vertical'?`1600 × ${S.length}`:`${S.length} × 960`;
    const message=S.phase==='failed'?'画面变化较大，无法连接下一段。已有内容已保留。':S.phase==='target'?'原窗口已变化。重新确认后才能继续。':paused?'内容已保留，可以继续或完成。':S.auto?'正在向已选区域滚动；你随时可以暂停。':'在选区内滚动页面，完成后检查长图。';
    const offset=Math.min(260,(S.frames-1)*53);
    return `<div class="scroll-target ${S.axis==='horizontal'?'horizontal':''}" id="scroll-target" aria-label="可滚动的捕获区域"><div style="transform:translate${S.axis==='vertical'?'Y':'X'}(-${offset}px)">${documentContent()}</div></div><div class="scroll-region"><i class="region-corner"></i><i class="region-corner"></i><i class="region-corner"></i><i class="region-corner"></i><span class="dimension-label">${S.axis==='vertical'?'纵向':'横向'}长截图</span></div><aside class="scroll-preview glass"><div class="preview-title"><span>已捕获</span><span>${S.frames} 段</span></div><div class="preview-paper" style="height:${Math.min(240,110+S.frames*18)}px"><b></b>${'<i></i>'.repeat(S.frames*5+5)}</div><div class="preview-check">${lengthText} px</div></aside><div class="scroll-control glass" id="scroll-control" tabindex="0" aria-label="长截图控制条"><div class="inline-row space-between"><div class="scroll-status"><span class="status-dot ${paused||failed?'paused':''}"></span><span>${title}</span></div><span class="scroll-dimension">${lengthText} px</span></div><div class="scroll-message">${message}</div><div class="inline-row space-between"><div>${button('cancel-scroll','取消','close')}</div><div class="inline-row">${failed?`${button('retry-scroll',S.phase==='target'?'重新确认':'重试连接','play','filled')}${button('finish-scroll','保留已有内容','check','primary')}`:`${!S.auto&&!paused?button('auto-scroll','自动滚动','spark'):''}${button('pause-scroll',paused?'继续':'暂停',paused?'play':'pause')}${button('finish-scroll','完成','check','primary')}`}</div></div></div>`;
  }
  function inkMarkup() {
    const h=S.lastWasLong?1030:430;
    const content=S.annotations.map(a=> {
      const x2=a.x+a.w,y2=a.y+a.h;
      let mark='';
      if(a.tool==='arrow') mark=`<path d="M${a.x} ${a.y} L${x2} ${y2}" marker-end="url(#arrow-head)"/>`;
      else if(a.tool==='ellipse') mark=`<ellipse cx="${a.x+a.w/2}" cy="${a.y+a.h/2}" rx="${Math.abs(a.w/2)}" ry="${Math.abs(a.h/2)}"/>`;
      else if(a.tool==='text') mark=`<text x="${a.x}" y="${a.y+20}" style="fill:${a.color}">${esc(a.text)}</text>`;
      else if(a.tool==='number') mark=`<circle cx="${a.x+13}" cy="${a.y+13}" r="13" fill="${a.color}" stroke="none"/><text x="${a.x+13}" y="${a.y+19}" text-anchor="middle" style="fill:white;font-size:15px">${a.number}</text>`;
      else if(a.tool==='pencil') mark=`<polyline points="${a.points.map(p=>p.join(',')).join(' ')}"/>`;
      else mark=`<rect x="${Math.min(a.x,x2)}" y="${Math.min(a.y,y2)}" width="${Math.abs(a.w)}" height="${Math.abs(a.h)}" rx="${a.tool==='crop'?0:2}" class="${a.tool==='mask'?'mask':a.tool==='crop'?'crop':''}"/>`;
      return `<g class="annotation" data-id="${a.id}" stroke="${a.color}" stroke-width="3">${mark}</g>${S.selected===a.id?`<rect class="select-ring" x="${Math.min(a.x,x2)-5}" y="${Math.min(a.y,y2)-5}" width="${Math.max(25,Math.abs(a.w))+10}" height="${Math.max(25,Math.abs(a.h))+10}"/>`:''}`;
    }).join('');
    return `<svg class="annotation-layer" id="annotation-layer" data-tool="${S.tool}" viewBox="0 0 550 ${h}" preserveAspectRatio="none" aria-label="可标注图片画布"><defs><marker id="arrow-head" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M0 0 10 5 0 10" fill="none" stroke="${S.color}" stroke-width="2"/></marker></defs>${content}</svg>`;
  }
  function editorMarkup() {
    const tools=[['select','选择 V'],['arrow','箭头 A'],['rect','矩形 R'],['ellipse','椭圆 O'],['text','文字 T'],['pencil','画笔 P'],['number','编号 N'],['mask','遮盖 B'],['crop','裁剪 C']];
    const bytes=outputDimensions();
    const fitLabel=S.lastWasLong?(S.axis==='vertical'?'适合宽度':'适合高度'):'适合窗口';
    return `<section class="editor surface"><header class="window-title"><div class="inline-row">${glyphButton('close-editor','关闭编辑器','close')}${traffic}</div><div class="title-center">${S.lastWasLong?'长截图':'截图'} ${S.dirty?'<span class="dirty-dot"></span><span class="tertiary small">未保存</span>':''}</div><div class="editor-top-actions">${button('ocr','取字','text')}${button('translate','翻译','translate')}${button('pin','贴图','pin')}</div></header><div class="editor-canvas" id="editor-canvas"><div class="capture-sheet ${S.lastWasLong?'':'short'}" id="capture-sheet" style="width:${550*S.zoom}px">${documentContent()}${inkMarkup()}</div></div>${S.tool!=='select'?`<div class="tool-options glass">${['#d45449','#568ab3','#91a76a','#f1cf70'].map(c=>`<button class="color-dot ${S.color===c?'active':''}" data-color="${c}" aria-label="标注颜色 ${c}" style="--swatch:${c}"></button>`).join('')}<span>${S.tool==='mask'?'实色遮盖':'3 px'}</span></div>`:''}<div class="canvas-tip">${S.tool==='select'?'选择工具可移动标注 · 长图可向下滚动查看':S.tool==='text'?'点击图片输入文字':S.tool==='number'?'点击图片添加编号':'在图片上拖动绘制 · Command-Z 撤销'}</div><footer class="editor-footer"><div class="tool-row"><div class="tool-group glass">${tools.map(([tool,label])=>`<button class="native-button ${S.tool===tool?'active':''}" data-tool="${tool}" title="${label}" aria-label="${label}" aria-pressed="${S.tool===tool}">${icon(tool)}</button>`).join('')}<span class="tool-separator"></span>${glyphButton('undo','撤销','undo',S.annotations.length?'':'is-disabled')}${glyphButton('redo','重做','redo',S.redo.length?'':'is-disabled')}</div><div class="output-group glass">${button('save','保存','save')}${button('copy','复制','copy','primary')}</div></div><div class="editor-info"><span>${bytes} px · 原始尺寸</span><div class="inline-row">${button('fit',fitLabel,'')}${button('zoom-out','−','')}<span>${Math.round(S.zoom*100)}%</span>${button('zoom-in','+','')}</div></div></footer></section>`;
  }
  function pinMarkup() {
    return `<div class="pin-frame" id="pin-frame" style="opacity:${S.pinOpacity/100}" aria-label="可拖动的截图贴图"><div class="pin-sheet">${documentContent()}${inkMarkup()}</div><div class="pin-controls glass">${glyphButton('copy-pin','复制贴图','copy')}${glyphButton('edit-pin','编辑贴图','pencil')}${glyphButton('close-pin','关闭贴图','close')}</div></div><div class="pin-opacity glass"><span>透明度</span><input id="pin-opacity" type="range" min="30" max="100" value="${S.pinOpacity}" aria-label="贴图透明度"><span id="opacity-value">${S.pinOpacity}%</span></div><p class="pin-caption">拖动移动 · 滚轮缩放 · 点击别的应用后保持可见</p>`;
  }
  function ocrMarkup() {
    const bytes=new TextEncoder().encode(S.ocr).length;
    const result=S.showTranslation?`<div class="translation-label"><span>${S.translated?'译文':'正在翻译'}</span>${S.translated?glyphButton('copy-translation','复制译文','copy'):''}</div><div class="translation-result">${S.translated?esc(sampleEnglish):'<div class="loading-text"><span class="progress-wave"></span>正在翻译…</div>'}</div>`:'';
    return `<section class="text-panel surface"><div class="window-title"><div class="window-heading">${glyphButton('back-editor','返回编辑','back')}<strong>截图文字</strong></div><div class="inline-row"><select id="translation-engine" class="native-select" aria-label="翻译引擎"><option ${S.engine==='Apple'?'selected':''}>Apple</option><option ${S.engine==='AI'?'selected':''}>AI</option></select>${glyphButton('retry-ocr','重新识别','history')}${glyphButton('close-text','关闭文字面板','close')}</div></div><div class="text-panel-content"><div class="source-chip">${icon('image')}<span>来自截图 · 切换应用后保留</span></div><textarea id="ocr-input" class="recognition-input" aria-label="识别的文字">${esc(S.ocr)}</textarea>${S.ocrNotice?`<div class="inline-warning" role="status">${esc(S.ocrNotice)}</div>`:''}${result}<div class="text-panel-footer"><span class="tertiary small" id="ocr-count">${bytes.toLocaleString()} bytes</span><div class="inline-row">${button('copy-text','复制文字','copy')}${button('translate-text',S.showTranslation?'重新翻译':'翻译','translate','primary')}</div></div></div></section>`;
  }
  function historyMarkup() {
    return `<section class="history-panel surface"><div class="window-title"><div class="window-heading">${glyphButton('launcher','返回入口','back')}<strong>Screenshot History</strong></div>${glyphButton('settings','截图设置','settings')}</div><div class="section-label"><span>最近截图</span><span>${S.history.length} 项</span></div><div class="history-list">${S.history.slice(0,6).map((item,i)=>`<button class="history-row" data-history="${i}" aria-label="打开 ${esc(item.name)}"><span class="history-thumb">${'<i></i>'.repeat(7)}</span><span class="history-copy"><strong>${esc(item.name)}</strong><small>${esc(item.dimension)} px</small></span><span class="history-tag">${item.editable?'可编辑原稿':'平面图片'}</span><span class="history-time">${item.time}</span></button>`).join('')}</div><div class="history-foot"><span>平面图片可添加新标注</span><span>保留 7 天</span></div></section>`;
  }
  function settingsMarkup() {
    const toggle=(id,value,label)=>`<input class="toggle" type="checkbox" id="${id}" aria-label="${label}" ${value?'checked':''}>`;
    return `<section class="settings-window"><div class="window-title"><div class="inline-row">${glyphButton('launcher','关闭设置','close')}${traffic}</div><strong>Capture</strong><span></span></div><div class="settings-body"><aside class="settings-sidebar"><p>通用</p><p>剪贴板</p><p class="active">Capture</p><p>Translation</p><p>快捷键</p><p>权限</p></aside><div class="settings-main"><div class="settings-section-title">功能</div><div class="settings-card"><label class="settings-row"><span>启用 Capture<small>只在你发起操作时捕获</small></span>${toggle('setting-enabled',S.enabled,'启用 Capture')}</label></div><div class="settings-section-title">输出</div><div class="settings-card"><div class="settings-row"><span>图片格式</span><select id="setting-format" aria-label="图片格式">${['PNG','JPEG','HEIC'].map(f=>`<option ${S.format===f?'selected':''}>${f}</option>`).join('')}</select></div><label class="settings-row"><span>复制后关闭编辑器</span>${toggle('setting-copy-close',S.copyClose,'复制后关闭编辑器')}</label><label class="settings-row"><span>包含鼠标指针</span>${toggle('setting-cursor',S.cursor,'包含鼠标指针')}</label></div><div class="settings-section-title">长截图</div><div class="settings-card"><div class="settings-row"><span>默认方向</span><select id="setting-axis" aria-label="默认滚动方向"><option value="vertical" ${S.axis==='vertical'?'selected':''}>纵向</option><option value="horizontal" ${S.axis==='horizontal'?'selected':''}>横向</option></select></div><div class="settings-row"><span>启动方式<small>自动滚动需在本次捕获中开启</small></span><span>手动</span></div></div><div class="settings-section-title">历史</div><div class="settings-card"><div class="settings-row"><span>保留时间</span><span>7 天 · 最多 512 MiB</span></div><label class="settings-row"><span>保留可编辑原稿<small>包含原图和标注，也包含打码前内容</small></span>${toggle('setting-raw',S.retainRaw,'保留可编辑原稿')}</label></div><div class="settings-section-title">权限</div><div class="settings-card"><div class="settings-row"><span>屏幕捕获</span><span>${S.permission?'已允许':'未允许'}</span></div><div class="settings-row"><span>自动滚动<small>首次主动使用时申请辅助功能权限</small></span><span>按需</span></div></div></div></div></section>`;
  }
  function renderDialog() {
    const d=S.dialog;
    if(!d) {dialogRoot.innerHTML='';return;}
    let title='',body='',actions='',symbol='capture',extra='';
    if(d==='permission'){title='允许屏幕捕获';body='Tinycast 需要此权限来截取你选择的区域。已有图片仍然可以编辑和贴图。';symbol='lock';actions=button('dismiss-dialog','稍后','','filled')+button('grant-permission','前往系统设置','','primary');}
    if(d==='permission-return'){title='权限已更新';body='准备好后，重新开始本次捕获。';actions=button('dismiss-dialog','取消','','filled')+button('retry-capture','重新检查并开始','','primary');}
    if(d==='discard-scroll'){title='保留已捕获的内容？';body='本次已经捕获了多个片段。你可以先保留结果，或丢弃并退出。';symbol='scroll';actions=button('dismiss-dialog','返回','','filled')+button('discard-scroll','丢弃','','danger')+button('keep-scroll','保留已有内容','','primary');}
    if(d==='close-editor'){title=S.lastWasLong&&!S.annotations.length?'保留这张长截图？':'保存这次编辑？';body=S.lastWasLong&&!S.annotations.length?'长截图还没有输出。保存草稿后可以继续编辑。':'当前图片还有未输出的修改。保存草稿后可以继续编辑。';actions=button('dismiss-dialog','取消','','filled')+button('discard-editor','丢弃','','danger')+button('save-draft','保存草稿','','primary');}
    if(d==='save'){title='保存图片';body='导出当前图片和标注。';symbol='save';extra=`<input id="save-name" aria-label="文件名" value="Tinycast-${S.lastWasLong?'长截图':'截图'}"><select class="native-select" id="save-format" aria-label="保存格式">${['PNG','JPEG','HEIC'].map(f=>`<option ${S.format===f?'selected':''}>${f}</option>`).join('')}</select>`;actions=button('dismiss-dialog','取消','','filled')+button('confirm-save','保存','','primary');}
    if(d==='save-failed'){title='图片未能保存';body='目标位置暂时不可写。图片与标注仍然保留，你可以重试或选择其他位置。';symbol='warn';actions=button('dismiss-dialog','返回编辑','','filled')+button('retry-save','重试','','primary');}
    dialogRoot.innerHTML=`<div class="dialog-backdrop"><section class="dialog glass" role="dialog" aria-modal="true" aria-label="${title}"><div class="dialog-symbol">${icon(symbol)}</div><h2>${title}</h2><p>${body}</p>${extra}<div class="dialog-actions ${['close-editor','discard-scroll'].includes(d)?'stack':''}">${actions}</div></section></div>`;
    dialogRoot.querySelector('input, button')?.focus({preventScroll:true});
  }
  function render() {
    const retainScrollFocus=S.scene==='scroll'&&document.activeElement?.closest('#scroll-control');
    scope.abort();scope=new AbortController();
    const templates={launcher:launcherMarkup,selection:selectionMarkup,scroll:scrollMarkup,editor:editorMarkup,pin:pinMarkup,ocr:ocrMarkup,history:historyMarkup,settings:settingsMarkup,done:()=>'<div class="done-tag">继续你的工作</div>'};
    root.innerHTML=templates[S.scene]();
    const current=S.scene==='translation'?'ocr':S.scene;
    document.querySelectorAll('[data-scene]').forEach(b=>{if(b.dataset.scene===current)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');});
    const [label,detail]=captions[S.scene];
    document.getElementById('scene-caption').textContent=detail;
    document.getElementById('flow-label').textContent=label;
    document.getElementById('flow-detail').textContent=detail;
    document.getElementById('demo-controls').innerHTML=S.scene==='scroll'?'<button class="review-button" data-action="simulate-scroll">模拟滚动一段 ↓</button><button class="review-button" data-action="restart-scroll">重新选择区域</button>':S.scene==='editor'?'<button class="review-button" data-action="sample-annotation">添加示例标注</button>':S.scene==='done'?'<button class="review-button" data-action="launcher">返回入口</button>':'';
    bindScene();
    renderDialog();
    if(retainScrollFocus&&!S.dialog)root.querySelector('#scroll-control')?.focus({preventScroll:true});
  }
  function on(selector,event,fn,options={}) {root.querySelector(selector)?.addEventListener(event,fn,{...options,signal:scope.signal});}
  function bindScene() {
    on('#command-search','input',e=>{const start=e.target.selectionStart;S.query=e.target.value;S.selectedCommand=0;render();const input=root.querySelector('#command-search');input.focus();input.setSelectionRange(start,start);});
    on('#capture-axis','change',e=>{S.axis=e.target.value;});
    on('#scroll-target','wheel',e=>{e.preventDefault();if(Date.now()-lastWheel<300)return;lastWheel=Date.now();if(Math.abs(e.deltaY)+Math.abs(e.deltaX)>2)advance();},{passive:false});
    on('#ocr-input','input',e=>{
      S.ocr=e.target.value;S.ocrNotice='';S.generation++;S.showTranslation=false;S.translated=false;
      const counter=root.querySelector('#ocr-count');if(counter)counter.textContent=`${new TextEncoder().encode(S.ocr).length.toLocaleString()} bytes`;
      root.querySelector('.inline-warning')?.remove();root.querySelector('.translation-label')?.remove();root.querySelector('.translation-result')?.remove();
      const translate=root.querySelector('[data-action="translate-text"]');
      if(translate){translate.querySelector('.button-word').textContent='翻译';translate.setAttribute('aria-label','翻译');translate.title='翻译';}
    });
    on('#pin-opacity','input',e=>{S.pinOpacity=Number(e.target.value);root.querySelector('#pin-frame').style.opacity=S.pinOpacity/100;root.querySelector('#opacity-value').textContent=`${S.pinOpacity}%`;});
    on('#pin-frame','wheel',e=>{e.preventDefault();const frame=e.currentTarget;const width=Math.max(180,Math.min(root.clientWidth*.85,frame.offsetWidth*(e.deltaY<0?1.07:.93)));frame.style.width=`${width}px`;frame.style.height=`${width*1.065}px`;frame.querySelector('.pin-sheet').style.transform=`scale(${width/550})`;},{passive:false});
    on('#translation-engine','change',e=>{S.engine=e.target.value;if(S.showTranslation)requestTranslate();});
    [['#setting-enabled','enabled'],['#setting-copy-close','copyClose'],['#setting-cursor','cursor'],['#setting-raw','retainRaw']].forEach(([id,key])=>on(id,'change',e=>{S[key]=e.target.checked;}));
    on('#setting-format','change',e=>{S.format=e.target.value;});
    on('#setting-axis','change',e=>{S.axis=e.target.value;});
    on('#selection-frame','pointerdown',startSelection);
    on('#annotation-layer','pointerdown',startAnnotation);
    on('#pin-frame','pointerdown',startPin);
    if(S.scene==='editor'){
      const undo=root.querySelector('[data-action="undo"]'),redo=root.querySelector('[data-action="redo"]');
      undo.disabled=!S.annotations.length;redo.disabled=!S.redo.length;
    }
  }

  function requestCapture(intent) {
    if(!S.enabled){notify('请先在 Capture 设置中启用功能',true);return;}
    S.intent=intent;
    if(!S.permission){S.dialog='permission';renderDialog();return;}
    if(intent==='full'){S.lastWasLong=false;S.annotations=[];S.dirty=false;switchScene('editor');return;}
    S.selection=null;S.selectionWindow=false;switchScene('selection');
  }
  function runCommand(id) {
    if(id==='history'){switchScene('history');return;}
    if(!S.enabled){notify('请先在 Capture 设置中启用功能',true);return;}
    if(id==='edit'){S.lastWasLong=false;S.annotations=[];S.dirty=false;switchScene('editor');return;}
    if(id==='pin'){switchScene('pin');return;}
    requestCapture(id);
  }
  function advance() {
    if(S.scene!=='scroll'||S.phase!=='running')return;
    if(S.length>=12000){stopAuto();S.phase='paused';notify('已达到演示长度，已有内容已保留');render();return;}
    S.frames++;S.length+=S.axis==='vertical'?740:620;render();
  }
  function startAuto() {
    S.auto=true;S.phase='running';render();
    clearInterval(autoTimer);autoTimer=setInterval(()=>{if(S.scene==='scroll'&&S.auto)advance();},1200);
  }
  function finishScroll() {stopAuto();S.lastWasLong=true;S.annotations=[];S.redo=[];S.dirty=true;S.zoom=1;switchScene('editor');}
  function outputDimensions() {
    return S.lastWasLong?(S.axis==='vertical'?`1600 × ${S.length}`:`${S.length} × 960`):'1440 × 960';
  }
  function recordHistory(draft=false) {
    const editable=draft||S.retainRaw;
    S.history.unshift({name:draft?'发布检查清单 · 草稿':'发布检查清单',dimension:outputDimensions(),axis:S.axis,time:'刚刚',editable,long:S.lastWasLong,annotations:editable?structuredClone(S.annotations):[]});
  }
  function requestTranslate() {
    const input=root.querySelector('#ocr-input');
    const text=input&&input.selectionEnd>input.selectionStart?input.value.slice(input.selectionStart,input.selectionEnd):S.ocr;
    if(!text.trim()){S.ocrNotice='没有可翻译的文字。可以重新选择区域。';render();return;}
    if(new TextEncoder().encode(text).length>12000){S.ocrNotice='内容过长，请选中一部分再翻译。不会自动截断。';render();return;}
    S.translationInput=text;S.translated=false;S.showTranslation=true;render();finishTranslation();
  }
  function finishTranslation() {
    const token=S.generation;
    setTimeout(()=>{if(S.scene!=='ocr'||token!==S.generation||!S.showTranslation)return;S.translated=true;render();},650);
  }
  function sampleAnnotation() {
    S.annotations.push({id:nextAnnotation++,tool:'rect',x:37,y:159,w:435,h:65,color:S.color});
    S.annotations.push({id:nextAnnotation++,tool:'arrow',x:424,y:310,w:-76,h:-80,color:S.color});
    S.redo=[];S.dirty=true;render();
  }
  const actions={
    'launcher':()=>switchScene('launcher'), 'settings':()=>switchScene('settings'),
    'run-selected':()=>{const c=commandRows()[S.selectedCommand];if(c)runCommand(c[0]);},
    'selection-mode':()=>{S.selectionWindow=!S.selectionWindow;S.selection=null;render();},
    'selection-scroll':()=>{S.intent='scroll';render();},
    'confirm-selection':()=>{
      if(S.intent==='scroll'){stopAuto();S.phase='running';S.frames=1;S.length=S.axis==='vertical'?960:1600;switchScene('scroll');}
      else if(S.intent==='ocr'||S.intent==='translate'){S.ocr=sampleText;S.ocrNotice='';S.showTranslation=false;switchScene('ocr');if(S.intent==='translate')requestTranslate();}
      else {S.lastWasLong=false;S.annotations=[];S.redo=[];S.dirty=false;recordHistory();switchScene('done');notify('已复制图片');}
    },
    'edit-selection':()=>{S.lastWasLong=false;S.annotations=[];S.redo=[];S.dirty=false;switchScene('editor');},
    'cancel-selection':()=>switchScene('launcher'), 'simulate-scroll':advance,
    'restart-scroll':()=>{stopAuto();requestCapture('scroll');}, 'auto-scroll':startAuto,
    'pause-scroll':()=>{if(S.phase==='paused'){S.phase='running';render();}else{stopAuto();S.phase='paused';render();}},
    'retry-scroll':()=>{S.phase='running';render();}, 'finish-scroll':finishScroll, 'keep-scroll':finishScroll,
    'cancel-scroll':()=>{stopAuto();if(S.frames>1){S.phase='paused';S.dialog='discard-scroll';render();}else switchScene('launcher');},
    'discard-scroll':()=>switchScene('launcher'),
    'close-editor':()=>{if(S.dirty){S.dialog='close-editor';renderDialog();}else switchScene('done');},
    'discard-editor':()=>{S.annotations=[];S.redo=[];switchScene('done');},
    'save-draft':()=>{recordHistory(true);S.dirty=false;switchScene('done');notify('草稿已保留');},
    'save':()=>{S.dialog='save';renderDialog();},
    'confirm-save':()=>{S.format=document.getElementById('save-format')?.value||S.format;if(S.failure==='save'){S.dialog='save-failed';renderDialog();return;}S.dirty=false;recordHistory();S.dialog=null;render();notify(`已保存 ${S.format} 图片`);},
    'retry-save':()=>{S.failure='none';document.getElementById('failure-scenario').value='none';S.dialog='save';renderDialog();},
    'copy':()=>{S.dirty=false;recordHistory();if(S.copyClose)switchScene('done');else render();notify('已复制图片');},
    'pin':()=>{S.pinOpacity=100;switchScene('pin');}, 'copy-pin':()=>notify('已复制贴图'),
    'edit-pin':()=>{S.dirty=false;switchScene('editor');}, 'close-pin':()=>switchScene('done'),
    'ocr':()=>{S.ocr=sampleText;S.ocrNotice='';S.showTranslation=false;switchScene('ocr');},
    'translate':()=>{S.ocr=sampleText;S.showTranslation=false;switchScene('ocr');requestTranslate();},
    'translate-text':requestTranslate,
    'copy-text':()=>notify('已复制文字'), 'copy-translation':()=>notify('已复制译文'),
    'back-editor':()=>switchScene('editor'), 'back-ocr':()=>switchScene('ocr'), 'close-text':()=>switchScene('done'),
    'retry-ocr':()=>{S.ocr=sampleText;S.ocrNotice='';S.showTranslation=false;S.generation++;render();notify('已更新识别结果');},
    'undo':()=>{if(S.annotations.length){S.redo.push(S.annotations.pop());S.selected=null;S.dirty=true;render();}},
    'redo':()=>{if(S.redo.length){S.annotations.push(S.redo.pop());S.dirty=true;render();}},
    'sample-annotation':sampleAnnotation,
    'fit':()=>{S.zoom=1;render();}, 'zoom-in':()=>{S.zoom=Math.min(2,S.zoom+.1);render();}, 'zoom-out':()=>{S.zoom=Math.max(.5,S.zoom-.1);render();},
    'dismiss-dialog':()=>{S.dialog=null;renderDialog();},
    'grant-permission':()=>{S.permission=true;S.dialog='permission-return';renderDialog();},
    'retry-capture':()=>{S.dialog=null;requestCapture(S.intent);},
  };

  studio.addEventListener('click',event=> {
    const scene=event.target.closest('[data-scene]');
    if(scene){switchScene(scene.dataset.scene,true);return;}
    const command=event.target.closest('[data-command]');if(command){runCommand(command.dataset.command);return;}
    const tool=event.target.closest('[data-tool]');
    if(tool?.tagName==='BUTTON'){S.tool=tool.dataset.tool;S.selected=null;render();return;}
    const color=event.target.closest('[data-color]');if(color){S.color=color.dataset.color;render();return;}
    const row=event.target.closest('[data-history]');if(row){const h=S.history[Number(row.dataset.history)];S.lastWasLong=h.long;S.axis=h.axis||'vertical';S.length=Number(h.dimension.split('×')[S.axis==='vertical'?1:0]);S.annotations=structuredClone(h.annotations);S.redo=[];S.dirty=false;S.zoom=1;switchScene('editor');notify(h.editable?'已打开可编辑原稿':'已打开平面图片，可添加新标注');return;}
    const action=event.target.closest('[data-action]');if(action&&!action.disabled)actions[action.dataset.action]?.();
  });
  document.getElementById('theme-toggle').addEventListener('click',event=> {
    const light=studio.dataset.theme==='dark';studio.dataset.theme=light?'light':'dark';
    event.currentTarget.textContent=light?'深色外观':'浅色外观';event.currentTarget.setAttribute('aria-label',`切换${light?'深':'浅'}色外观`);
  });
  document.getElementById('apply-scenario').addEventListener('click',()=> {
    const value=document.getElementById('failure-scenario').value;S.failure=value;
    if(value==='stitch'||value==='target'){stopAuto();S.scene='scroll';S.frames=Math.max(3,S.frames);S.length=Math.max(2840,S.length);S.phase=value==='stitch'?'failed':'target';render();}
    else if(value==='permission'){stopAuto();S.permission=false;S.scene='launcher';S.intent='scroll';S.dialog='permission';render();}
    else if(value==='longtext'){S.ocr=sampleText.repeat(45);S.ocrNotice='';switchScene('ocr');}
    else if(value==='save'){S.scene='editor';S.dialog='save';render();}
    else{S.permission=true;switchScene('scroll',true);}
  });

  function canvasPoint(event,svg) {
    const r=svg.getBoundingClientRect();
    return {x:Math.max(0,Math.min(550,(event.clientX-r.left)*550/r.width)),y:Math.max(0,Math.min(S.lastWasLong?1030:430,(event.clientY-r.top)*(S.lastWasLong?1030:430)/r.height))};
  }
  function startAnnotation(event) {
    if(S.dialog||event.button!==0)return;
    const svg=event.currentTarget,p=canvasPoint(event,svg);
    if(S.tool==='text'){showTextInput(p);return;}
    if(S.tool==='number'){S.annotations.push({id:nextAnnotation++,tool:'number',x:p.x,y:p.y,w:26,h:26,number:S.annotations.filter(a=>a.tool==='number').length+1,color:S.color});S.redo=[];S.dirty=true;render();return;}
    if(S.tool==='select'){
      const node=event.target.closest('[data-id]');if(!node){S.selected=null;renderInk();return;}
      const a=S.annotations.find(a=>a.id===Number(node.dataset.id));S.selected=a.id;
      pointer={type:'move-annotation',id:event.pointerId,start:p,original:structuredClone(a),annotation:a,svg};renderInk();
    }else{
      const a={id:nextAnnotation++,tool:S.tool,x:p.x,y:p.y,w:0,h:0,color:S.color,points:[[p.x,p.y]]};
      S.annotations.push(a);pointer={type:'draw',id:event.pointerId,start:p,annotation:a,svg};
    }
    svg.setPointerCapture(event.pointerId);event.preventDefault();
  }
  function renderInk() {
    const old=root.querySelector('#annotation-layer');if(!old)return;
    const holder=document.createElement('div');holder.innerHTML=inkMarkup();
    old.innerHTML=holder.firstElementChild.innerHTML;
  }
  function showTextInput(p) {
    root.querySelector('.annotation-textbox')?.remove();
    const box=document.createElement('div');box.className='annotation-textbox';
    box.style.left=`${p.x/550*100}%`;box.style.top=`${p.y/(S.lastWasLong?1030:430)*100}%`;
    box.innerHTML='<input aria-label="标注文字" placeholder="输入文字"><button type="button" aria-label="完成文字标注">完成</button>';
    root.querySelector('#capture-sheet').appendChild(box);
    const input=box.querySelector('input');
    const finish=()=>{const value=input.value.trim();if(value){S.annotations.push({id:nextAnnotation++,tool:'text',x:p.x,y:p.y,w:Math.max(80,value.length*17),h:26,text:value,color:S.color});S.redo=[];S.dirty=true;}render();};
    box.querySelector('button').addEventListener('click',finish);
    input.addEventListener('keydown',e=>{if(e.isComposing)return;if(e.key==='Enter'){e.preventDefault();e.stopPropagation();finish();}if(e.key==='Escape'){e.stopPropagation();box.remove();}});input.focus();
  }
  function startSelection(event) {
    if(S.selectionWindow||event.button!==0)return;
    const r=root.getBoundingClientRect();pointer={type:'selection',id:event.pointerId,start:{x:event.clientX-r.left,y:event.clientY-r.top},element:event.currentTarget};
    event.currentTarget.setPointerCapture(event.pointerId);event.preventDefault();
  }
  function startPin(event) {
    if(event.target.closest('button')||event.button!==0)return;
    pointer={type:'pin',id:event.pointerId,start:{x:event.clientX,y:event.clientY},left:event.currentTarget.offsetLeft,top:event.currentTarget.offsetTop,element:event.currentTarget};
    event.currentTarget.setPointerCapture(event.pointerId);event.preventDefault();
  }
  document.addEventListener('pointermove',event=> {
    if(!pointer||pointer.id!==event.pointerId)return;
    if(pointer.type==='draw'||pointer.type==='move-annotation'){
      const p=canvasPoint(event,pointer.svg),a=pointer.annotation;
      if(pointer.type==='draw'){a.w=p.x-pointer.start.x;a.h=p.y-pointer.start.y;if(a.tool==='pencil')a.points.push([p.x,p.y]);}
      else{const dx=p.x-pointer.start.x,dy=p.y-pointer.start.y;a.x=pointer.original.x+dx;a.y=pointer.original.y+dy;if(a.tool==='pencil')a.points=pointer.original.points.map(([x,y])=>[x+dx,y+dy]);}
      renderInk();
    }else if(pointer.type==='selection'){
      const r=root.getBoundingClientRect(),x=Math.max(2,Math.min(r.width-2,event.clientX-r.left)),y=Math.max(40,Math.min(r.height-70,event.clientY-r.top));
      S.selection={x:Math.min(x,pointer.start.x),y:Math.min(y,pointer.start.y),w:Math.max(20,Math.abs(x-pointer.start.x)),h:Math.max(20,Math.abs(y-pointer.start.y))};
      Object.assign(pointer.element.style,{left:`${S.selection.x}px`,top:`${S.selection.y}px`,width:`${S.selection.w}px`,height:`${S.selection.h}px`});
      pointer.element.querySelector('.dimension-label').textContent=`${Math.round(S.selection.w*2)} × ${Math.round(S.selection.h*2)} px`;
    }else if(pointer.type==='pin'){
      const x=Math.max(0,Math.min(root.clientWidth-pointer.element.offsetWidth,pointer.left+event.clientX-pointer.start.x));
      const y=Math.max(0,Math.min(root.clientHeight-pointer.element.offsetHeight,pointer.top+event.clientY-pointer.start.y));
      pointer.element.style.left=`${x}px`;pointer.element.style.top=`${y}px`;
    }
  });
  document.addEventListener('pointerup',event=> {
    if(!pointer||pointer.id!==event.pointerId)return;
    if(pointer.type==='draw'){
      const a=pointer.annotation;if(Math.abs(a.w)+Math.abs(a.h)<8)S.annotations=S.annotations.filter(item=>item.id!==a.id);
      S.redo=[];S.dirty=true;pointer=null;render();return;
    }
    if(pointer.type==='move-annotation'){S.dirty=true;pointer=null;render();return;}
    pointer=null;
  });
  document.addEventListener('pointercancel',()=>{pointer=null;});

  document.addEventListener('keydown',event=> {
    if(event.isComposing)return;
    const editing=/^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName);
    if(S.dialog){if(event.key==='Escape'){event.preventDefault();S.dialog=null;renderDialog();}return;}
    if(S.scene==='launcher'&&['ArrowDown','ArrowUp','Enter'].includes(event.key)){
      event.preventDefault();if(event.key==='Enter'){actions['run-selected']();return;}
      S.selectedCommand=Math.max(0,Math.min(commandRows().length-1,S.selectedCommand+(event.key==='ArrowDown'?1:-1)));render();root.querySelector('#command-search')?.focus();root.querySelector('.command-row.selected')?.scrollIntoView({block:'nearest'});return;
    }
    if(editing)return;
    if(S.scene==='selection'){
      if(event.code==='Space'){event.preventDefault();actions['selection-mode']();}
      else if(event.key==='Enter'||((event.metaKey||event.ctrlKey)&&event.key.toLowerCase()==='c'&&S.intent==='capture')){event.preventDefault();actions['confirm-selection']();}
      else if(event.key==='Escape'){event.preventDefault();actions['cancel-selection']();}return;
    }
    if(S.scene==='scroll'&&document.activeElement?.closest('#scroll-control')){
      if(event.key==='Enter'){event.preventDefault();finishScroll();}else if(event.code==='Space'){event.preventDefault();actions['pause-scroll']();}else if(event.key==='Escape'){event.preventDefault();actions['cancel-scroll']();}return;
    }
    if(S.scene==='editor'){
      if(event.metaKey||event.ctrlKey){
        const key=event.key.toLowerCase();
        const action=key==='z'?(event.shiftKey?'redo':'undo'):key==='s'?'save':key==='c'?'copy':key==='w'?'close-editor':key==='0'?'fit':null;
        if(action){event.preventDefault();actions[action]();}return;
      }
      const map={v:'select',a:'arrow',r:'rect',o:'ellipse',t:'text',p:'pencil',n:'number',b:'mask',c:'crop'};
      if(map[event.key.toLowerCase()]){S.tool=map[event.key.toLowerCase()];render();}
      else if((event.key==='Delete'||event.key==='Backspace')&&S.selected){event.preventDefault();S.annotations=S.annotations.filter(a=>a.id!==S.selected);S.selected=null;S.dirty=true;render();}
      else if(event.key==='Escape'){event.preventDefault();if(S.selected){S.selected=null;render();}else if(S.tool!=='select'){S.tool='select';render();}else actions['close-editor']();}
    }
  });

  source.innerHTML=documentContent();
  render();
})();
