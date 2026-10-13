// GENERADO por tools/extraer_plano.py desde Field Reports (no editar a mano: se vuelve a generar).
// Dibuja el plano igual que Field Reports. 107 piezas.
/* eslint-disable */
const document = (typeof globalThis !== "undefined" && globalThis.document) || undefined;
  const $ = (sel, el) => { const d = el || (typeof document !== 'undefined' ? document : null); return d && d.querySelector ? d.querySelector(sel) : null; };
  function esc(str){ return String(str == null ? '' : str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;'); }
  const FP_PLANTAS = ['Basement', '1st Floor', '2nd Floor', '3rd Floor', 'Attic'];
  function fpPlantaDeNivel(data, lvl){
    const n = Math.max(1, +lvl || 1);
    const base = (data && data._nivelBase) || '';
    const i0 = FP_PLANTAS.indexOf(base);
    // SIN PLANTA DE PARTIDA NO SE INVENTA NINGUNA (18 sep 2026).
    //
    // Aquí decía "el nivel 1 es el primer piso" y devolvía '1st Floor'. Para el
    // sótano de la casa de Reccy eso es mentira, y era la ÚNICA línea de toda
    // la app capaz de escribir "1st Floor" encima de un sótano: de ahí salía el
    // "it just changed it to First Floor in all of them" que él reportó.
    //
    // Ahora se dice "Nivel N", que es lo único cierto — el orden del escaneo.
    // Quien quiera la suposición vieja tiene que pedirla a propósito, y solo
    // vale para CRUZAR datos, nunca para enseñar: fpPlantaSupuesta.
    if(i0 < 0) return 'Nivel ' + n;
    const i = i0 + (n - 1);
    return i < FP_PLANTAS.length ? FP_PLANTAS[i] : ('Nivel ' + n);
  }
  function fpPlantaSupuesta(data, lvl){
    const n = Math.max(1, +lvl || 1);
    if(data && data._nivelBase) return fpPlantaDeNivel(data, lvl);
    return (n <= FP_PLANTAS.length - 1) ? FP_PLANTAS[n] : ('Nivel ' + n);
  }
  function floorplanDominantAngle(rooms){
    let sumX = 0, sumY = 0;
    (rooms||[]).forEach(room => {
      (room.walls||[]).forEach(w => {
        const dx = w.end.x - w.start.x, dy = w.end.y - w.start.y;
        const len = Math.sqrt(dx*dx + dy*dy);
        if(len < 0.5) return; // ignore tiny/degenerate walls as noise
        const angle = Math.atan2(dy, dx);
        sumX += len * Math.cos(4*angle);
        sumY += len * Math.sin(4*angle);
      });
    });
    if(Math.abs(sumX) < 1e-6 && Math.abs(sumY) < 1e-6) return 0;
    return Math.atan2(sumY, sumX) / 4;
  }
  function fpTransformarInspeccion(insp, P, soloCuarto){
    if(!insp) return;
    const vale = k => soloCuarto == null || k === soloCuarto;
    (insp.keyframes || []).forEach(kf => {
      if(!kf || !vale(kf.roomIndex)) return;
      if(isFinite(kf.x) && isFinite(kf.z)){ const p = P(kf.x, kf.z); kf.x = p.x; kf.z = p.y; }
      if(isFinite(kf.hitX) && isFinite(kf.hitY)){ const p = P(kf.hitX, kf.hitY); kf.hitX = p.x; kf.hitY = p.y; }
      // La vista en el plano es (sin yaw, cos yaw): se gira el vector y se
      // vuelve a sacar el ángulo, sin adivinar signos.
      if(isFinite(kf.yaw)){ const v = P(Math.sin(kf.yaw), Math.cos(kf.yaw)); kf.yaw = Math.atan2(v.x, v.y); }
    });
    (insp.path || []).forEach(q => {
      if(!q || !vale(q.r) || !isFinite(q.x) || !isFinite(q.y)) return;
      const p = P(q.x, q.y); q.x = p.x; q.y = p.y;
    });
    // Las esquinas que el teléfono avisó, por cuarto: también giran.
    Object.keys(insp.scanCorners || {}).forEach(k => {
      if(!vale(Number(k))) return;
      (insp.scanCorners[k] || []).forEach(e => {
        if(!e || !isFinite(e.x) || !isFinite(e.y)) return;
        const p = P(e.x, e.y); e.x = p.x; e.y = p.y;
      });
    });
  }
  function floorplanAlignRooms(data){
    if(!data || !data.rooms) return;
    const rotateRooms = (roomList, angle, soloCuarto) => {
      if(Math.abs(angle) < 0.01) return;
      const cos = Math.cos(angle), sin = Math.sin(angle);
      const rot = p => ({ x: p.x*cos + p.y*sin, y: -p.x*sin + p.y*cos });
      const angleDeg = angle * 180 / Math.PI;
      roomList.forEach(room => {
        (room.walls||[]).forEach(w => { w.start = rot(w.start); w.end = rot(w.end); });
        (room.doors||[]).forEach(d => { d.position = rot(d.position); });
        (room.windows||[]).forEach(win => { win.position = rot(win.position); });
        (room.openings||[]).forEach(o => { o.position = rot(o.position); });
        (room.objects||[]).forEach(obj => {
          obj.center = rot(obj.center);
          obj.rotationDeg = (obj.rotationDeg||0) - angleDeg;
        });
      });
      fpTransformarInspeccion(data.inspection, (x, y) => rot({ x, y }), soloCuarto);
    };
    if(data.merged === false){
      // Unmerged rooms live in INDEPENDENT coordinate frames with
      // independent orientations - one pooled angle straightens none of
      // them. Each room gets its own dominant-angle rotation.
      data.rooms.forEach((room, i) => rotateRooms([room], floorplanDominantAngle([room]), i));
    }else{
      rotateRooms(data.rooms, floorplanDominantAngle(data.rooms));
    }
  }
  const FLOORPLAN_CATEGORY_ES = {
    storage: 'Storage', refrigerator: 'Refrigerator', stove: 'Stove', oven: 'Oven',
    dishwasher: 'Dishwasher', sink: 'Sink', washerDryer: 'Washer/Dryer',
    toilet: 'Toilet', bathtub: 'Bathtub', bed: 'Bed', sofa: 'Sofa', chair: 'Chair',
    table: 'Table', television: 'Television', fireplace: 'Fireplace', stairs: 'Stairs',
    unknown: 'Unknown'
  };
  function floorplanCategoryLabel(cat){
    return FLOORPLAN_CATEGORY_ES[cat] || cat || 'Unknown';
  }
  function floorplanLevels(data){
    // Deleted rooms don't create level tabs - a level whose only room
    // was voice-deleted would otherwise show up as an empty tab.
    const set = new Set((data.rooms||[]).filter(r => !r.deleted).map(r => r.level || 1));
    return Array.from(set).sort((a,b) => a-b);
  }
  let floorplanSelectedLevel = 1;
  let fpIdCounter = 0;
  function fpNewId(){ return 'man-' + Date.now().toString(36) + '-' + (fpIdCounter++); }
  let fpMeasurePrefs = { interior: true, openings: true, roomArea: true, furniture: false, extents: true };
  const FP_MOVABLE_CATEGORIES = ['bed', 'sofa', 'chair', 'table', 'television'];
  function fpBuildNodes(wallRefs){
    const nodes = [];
    const nodeOf = p => {
      for(const n of nodes){
        if(Math.hypot(n.x-p.x, n.y-p.y) <= 0.35){
          n.x = (n.x*n.refs.length + p.x)/(n.refs.length+1);
          n.y = (n.y*n.refs.length + p.y)/(n.refs.length+1);
          n.refs.push(p);
          return n;
        }
      }
      const n = {x: p.x, y: p.y, refs: [p]};
      nodes.push(n);
      return n;
    };
    const ends = wallRefs.map(wr => ({ wall: wr.wall, roomIdx: wr.roomIdx, a: nodeOf(wr.wall.start), b: nodeOf(wr.wall.end) }));
    return { nodes, ends };
  }
  function fpManualEditSummary(data){
    let wallsMoved = 0, cornersAdj = 0, wallsAdded = 0, opAdded = 0, opRemoved = 0, opMoved = 0, opRetyped = 0, furn = 0;
    // Las particiones de solo studs se cuentan por PAREJA, no por registro: el
    // corte deja una copia en cada mitad y aquí saldría "2 walls drawn by
    // hand" por una sola pared física.
    const studPairs = new Set();
    ((data && data.rooms)||[]).forEach(room => {
      if(room.deleted) return;
      (room.walls||[]).forEach(w => {
        if(w._studWall && w._studPairId) studPairs.add(w._studPairId);
        else if(w._added) wallsAdded++;
        else if(w._movedByHand) wallsMoved++;
        else if(w._geomEdited) cornersAdj++;
      });
      [].concat(room.doors||[], room.windows||[], room.openings||[]).forEach(o => {
        if(o._added && !o._removed) opAdded++;
        else if(o._removed && !o._added) opRemoved++;
        else if(o._movedByHand) opMoved++;
        else if(o._typeSetByHand) opRetyped++;
      });
      (room.objects||[]).forEach(o => { if(o._added || o._movedByHand || o._resizedByHand) furn++; });
    });
    const wallsRemoved = (data && data._removals && data._removals.walls) || 0;
    const water = ((data && data._waterMarks) || []).length;
    const studs = studPairs.size;
    const total = wallsMoved + cornersAdj + wallsAdded + opAdded + opRemoved + opMoved + opRetyped + furn + wallsRemoved + water + studs;
    if(!total) return null;
    const parts = [];
    if(studs) parts.push(`${studs} open stud partition${studs>1?'s':''} added on site, room split along ${studs>1?'them':'it'}`);
    if(wallsMoved) parts.push(`${wallsMoved} wall${wallsMoved>1?'s':''} moved`);
    if(cornersAdj) parts.push(`${cornersAdj} wall${cornersAdj>1?'s':''} adjusted at a corner`);
    if(wallsAdded) parts.push(`${wallsAdded} wall${wallsAdded>1?'s':''} drawn by hand`);
    if(wallsRemoved) parts.push(`${wallsRemoved} wall${wallsRemoved>1?'s':''} removed`);
    if(opAdded) parts.push(`${opAdded} door${opAdded>1?'s':''}/window${opAdded>1?'s':''} added`);
    if(opMoved) parts.push(`${opMoved} moved`);
    if(opRemoved) parts.push(`${opRemoved} removed`);
    if(opRetyped) parts.push(`${opRetyped} reclassified (door/window/passage)`);
    if(furn) parts.push(`${furn} furniture item${furn>1?'s':''} added or moved`);
    if(water){
      const byKind = {};
      (data._waterMarks||[]).forEach(m => { const k = m.kind || 'water'; byKind[k] = (byKind[k]||0) + 1; });
      const kindTxt = Object.keys(byKind).map(k => `${k} ${byKind[k]}`).join(', ');
      parts.push(`damage areas painted by hand (${kindTxt})`);
    }
    return { total, text: `Hand edits on this plan: ${parts.join(', ')}. Dimensions marked * were set by hand, not measured by LiDAR. Areas are recalculated from the edited walls.` };
  }
  const FP_QUANT = v => Math.round(v * 12) / 12; // nearest inch;
  let fpRenderMode = 'plan';
  let fpSheetExport = false;
  const FM_KINDS = {
    water:     { color: 'rgba(41,128,185,0.45)',  legend: 'WATER',      legendColor: '#2980b9' },
    moisture:  { color: 'rgba(127,179,213,0.5)',  legend: 'MOISTURE',   legendColor: '#5499c7' },
    mold:      { color: 'rgba(39,174,96,0.45)',   legend: 'MOLD',       legendColor: '#27ae60' },
    moldLight: { color: 'rgba(130,224,170,0.5)',  legend: 'MOLD RISK',  legendColor: '#52be80' },
    smoke:     { color: 'rgba(127,140,141,0.5)',  legend: 'SMOKE',      legendColor: '#7f8c8d' },
    fire:      { color: 'rgba(243,156,18,0.45)',  legend: 'FIRE',       legendColor: '#d68910' },
    damage:    { color: 'rgba(192,57,43,0.45)',   legend: 'DAMAGE',     legendColor: '#c0392b' }
  };
  const FM_KIND_ALIASES = { affected: 'moisture', wet: 'water', saturated: 'damage' };
  function fmKindDef(kind){
    return FM_KINDS[kind] || FM_KINDS[FM_KIND_ALIASES[kind]] || FM_KINDS.water;
  }
  const FP_BRUSH_KINDS = {
    water:  { color: 'rgba(41,128,185,0.4)',  legend: 'WATER EXTENT',  legendColor: '#2980b9' },
    mold:   { color: 'rgba(39,174,96,0.4)',   legend: 'MOLD',          legendColor: '#27ae60' },
    smoke:  { color: 'rgba(127,140,141,0.45)',legend: 'SMOKE',         legendColor: '#7f8c8d' },
    damage: { color: 'rgba(192,57,43,0.4)',   legend: 'DAMAGE',        legendColor: '#c0392b' }
  };
  let fpInspectionById = {};
  const FP_STUD_UMBRAL = 0.6;
  const FP_STUD_MIN_FOTOS = 2;
  const FP_STUD_BORDE_FT = 1;      // un punto a menos de esto del contorno es una pared que el plano YA tiene;
  const FP_STUD_LEJOS_FT = 2;      // un punto mucho más lejos que el más cercano pasó por el hueco entre studs;
  const FP_STUD_ESCUADRA_DEG = 30; // el eje de los puntos tiene que quedar a escuadra con la vista;
  function fpStudLineaPropuesta(data, roomIdx, puntos){
    const room = ((data && data.rooms) || [])[roomIdx];
    if(!room) return null;
    const poly = fpOrderedRoomPolygon(room);
    if(!poly || poly.length < 3) return null;
    // Solo puntos BIEN ADENTRO del cuarto. Un punto en el contorno, o a un
    // pie de él, es una pared que RoomPlan ya modeló (un flood cut en una
    // pared existente, o la pared del vecino vista por una puerta): la
    // pared que interesa es la que el plano NO tiene, y esa está en el
    // interior del cuarto juntado.
    let dentro = (puntos || []).filter(p => p && isFinite(p.x) && isFinite(p.y)
      && fpPointInPolygon(p, poly) && fpDistToPolygon(p, poly) > FP_STUD_BORDE_FT);
    if(!dentro.length) return null;
    // Una foto que miró por el HUECO entre dos studs pegó en la pared del
    // fondo, mucho más lejos de la cámara que las que pegaron en un stud.
    // Se quedan las cercanas (a menos de 2 ft de la más cercana).
    const conCamara = dentro.filter(p => isFinite(p.cx) && isFinite(p.cy));
    if(conCamara.length >= 2){
      const dist = p => Math.hypot(p.x - p.cx, p.y - p.cy);
      const minD = Math.min(...conCamara.map(dist));
      dentro = dentro.filter(p => !(isFinite(p.cx) && isFinite(p.cy)) || dist(p) <= minD + FP_STUD_LEJOS_FT);
    }
    const cx = dentro.reduce((s, p) => s + p.x, 0) / dentro.length;
    const cy = dentro.reduce((s, p) => s + p.y, 0) / dentro.length;
    let lejos = 0;
    for(let i = 0; i < dentro.length; i++) for(let j = i + 1; j < dentro.length; j++)
      lejos = Math.max(lejos, Math.hypot(dentro[i].x - dentro[j].x, dentro[i].y - dentro[j].y));
    // Hacia dónde miraba (media circular). En el plano la vista es
    // (sin yaw, cos yaw); la pared que se ve de frente corre perpendicular.
    const vistas = dentro.filter(p => isFinite(p.yaw));
    let vx = 0, vy = 0;
    if(vistas.length){
      vx = vistas.reduce((s, p) => s + Math.sin(p.yaw), 0); vy = vistas.reduce((s, p) => s + Math.cos(p.yaw), 0);
      const L = Math.hypot(vx, vy); if(L < 1e-6){ vx = 0; vy = 0; } else { vx /= L; vy /= L; }
    }
    const hayVista = vx !== 0 || vy !== 0;
    let ux, uy, base = null;
    if(dentro.length >= 2 && lejos >= 1.5){
      // El eje principal de los puntos (mínimos cuadrados ortogonales)...
      let sxx = 0, syy = 0, sxy = 0;
      dentro.forEach(p => { sxx += (p.x - cx) ** 2; syy += (p.y - cy) ** 2; sxy += (p.x - cx) * (p.y - cy); });
      const ang = 0.5 * Math.atan2(2 * sxy, sxx - syy);
      ux = Math.cos(ang); uy = Math.sin(ang); base = 'puntos';
      // ...pero solo si queda A ESCUADRA con la vista: una pared se mira de
      // frente, así que su eje es perpendicular a la vista. Si no, algún
      // punto no es de esta pared y manda la vista.
      if(hayVista){
        const fueraDeEscuadra = Math.asin(Math.min(1, Math.abs(ux * vx + uy * vy))) * 180 / Math.PI;
        if(fueraDeEscuadra > FP_STUD_ESCUADRA_DEG) base = null;
      }
    }
    if(!base){
      if(!hayVista) return null;
      ux = vy; uy = -vx; base = 'vista';
    }
    const a = { x: cx - ux * 0.5, y: cy - uy * 0.5 }, b = { x: cx + ux * 0.5, y: cy + uy * 0.5 };
    // La guía corta se estira de pared a pared y se endereza; y ANTES de
    // ofrecerla pasa por los mismos candados que el corte a mano (son
    // puros): un botón que siempre se niega no es una propuesta.
    const corte = fpCutRoomByLine(room, a, b);
    if(corte.error) return null;
    const cand = fpStudSplitCandidates(data, roomIdx, a, b);
    if(cand.error) return null;
    const san = fpStudSplitSanity({ room, m: cand.m0 }, { room: cand.roomA, m: fpRoomMeasurements(cand.roomA) },
                                  { room: cand.roomB, m: fpRoomMeasurements(cand.roomB) }, cand.cut.largo, cand.cut.cruces);
    if(!san.ok) return null;
    return { a, b, puntos: dentro.length, base, largo: corte.largo };
  }
  function fpStudIssues(data){
    const salida = [];
    const kfs = ((data && data.inspection && data.inspection.keyframes) || []).filter(k => k && typeof k.studScore === 'number');
    if(!kfs.length) return salida;
    ((data && data.rooms) || []).forEach((room, idx) => {
      if(!room || room.deleted || room._studReviewed) return;
      if((room.walls || []).some(w => w._studWall)) return;
      const fotos = kfs.filter(k => k.roomIndex === idx && k.studScore >= FP_STUD_UMBRAL)
        .sort((a, b) => b.studScore - a.studScore);
      if(fotos.length < FP_STUD_MIN_FOTOS) return;
      const roomName = room.roomName || `Room ${idx + 1}`;
      // Dónde estaba: los puntos a los que la cámara les apuntaba en esas
      // fotos, con la posición de la cámara (x, z del mundo = x, y del plano).
      const propuesta = fpStudLineaPropuesta(data, idx, fotos.filter(k => isFinite(k.hitX) && isFinite(k.hitY))
        .map(k => ({ x: k.hitX, y: k.hitY, yaw: k.yaw, cx: k.x, cy: k.z })));
      salida.push({ kind: 'studs', room: idx, kfId: fotos[0].id, ack: '_studReviewed', fotos: fotos.length, propuesta,
        text: `${esc(roomName)}: ${fotos.length} walkthrough photos show wall framing with the drywall off (studs). Was there a wall here that was torn out to the studs? `
          + (propuesta
              ? `The camera was pointing at that framing along a ${propuesta.largo.toFixed(1)} ft line across the room - tap "Propose the partition" to split the room there, or draw it yourself.`
              : `If so, draw the partition and split the room.`) });
    });
    return salida;
  }
  function floorplanValidate(data){
    const issues = [];
    ((data && data.rooms) || []).forEach((room, idx) => {
      if(room.deleted || !(room.walls||[]).length) return;
      const roomName = room.roomName || `Room ${idx+1}`;
      const lowConf = (room.walls||[]).filter(w => w.confidence === 'low').length;
      if(lowConf && !room._lowConfReviewed) issues.push({ kind: 'lowconf', room: idx, ack: '_lowConfReviewed', text: `${esc(roomName)}: ${lowConf} low-confidence wall${lowConf>1?'s':''} (red dashed) - verify the measurement or rescan that side.` });
      (room.openings||[]).forEach((op, oi) => {
        if(op._kindOverride || op._reviewed || op._removed) return;
        const w = floorplanOpeningEffectiveWidth(op) || 0;
        if(w < 1.5) issues.push({ kind: 'opening', room: idx, openingIdx: oi, text: `${esc(roomName)}: a very narrow opening (${fpFeetInches(w)}) - is it real? Classify it:` });
      });
      // Editor honesty checks: added items still carrying their default
      // size, and openings left dangling past the end of an edited wall.
      const wallsById2 = {};
      (room.walls||[]).forEach((w2, wi2) => { wallsById2[String(w2.id != null ? w2.id : wi2)] = w2; });
      [['door', room.doors], ['window', room.windows]].forEach(([kindName, list]) => {
        (list||[]).forEach(o => {
          if(o._removed) return;
          if(o._added && o._defaultSize){
            issues.push({ kind: 'defaultsize', room: idx, text: `${esc(roomName)}: an added ${kindName} still has its default size (${fpFeetInches(o.widthFt||0)}) - measure it and enter the real width.` });
          }
          const w2 = o.wallId != null ? wallsById2[String(o.wallId)] : null;
          if(w2 && o.position){
            const vx = w2.end.x-w2.start.x, vy = w2.end.y-w2.start.y;
            const len2 = vx*vx+vy*vy;
            if(len2 > 1e-6){
              const t = ((o.position.x-w2.start.x)*vx + (o.position.y-w2.start.y)*vy)/len2;
              if(t < -0.05 || t > 1.05) issues.push({ kind: 'dangling', room: idx, text: `${esc(roomName)}: a ${kindName} sits past the end of its edited wall - move it or remove it.` });
            }
          }
        });
      });
      const gapInfo = {};
      fpOrderedRoomPolygon(room, gapInfo);
      // A break another room's wall already covers is not a break - the
      // building is closed there (same recovery test AI Fix uses).
      const bigGapSegs = (gapInfo.bridgeSegs||[]).filter(g => g.d > 6 && !fpAiSegmentCoveredByOtherWalls(data, idx, g, room.level || 1));
      if(bigGapSegs.length && !room._gapReviewed){
        const biggest = bigGapSegs.reduce((m, g) => g.d > m.d ? g : m);
        // Our own evidence, from the walked path - nobody walks through a
        // wall. This never SILENCES the item (the honest direction is
        // always to keep asking), it says what we independently know.
        const walked = fpPathCrossesSegment(biggest, fpWalkedPath(data, room.level || 1), 4);
        // The corner the tech could not reach: if the two walls that reach
        // this break would meet at a square corner, offer THAT instead of
        // a single straight wall across the opening.
        const corner = walked ? null : fpInferCorner(room, biggest);
        issues.push({ kind: 'gap', room: idx, ack: '_gapReviewed', seg: biggest, corner: corner,
          text: `${esc(roomName)}: a ${fpFeetInches(biggest.d)} break in the room outline`
            + (walked
                ? ` - but you walked through it during the scan, so it is probably a doorway, not a missing wall.`
                : corner
                  ? (corner.kind === 'vertice'
                      ? ` - the two walls that reach it would meet at a ${corner.angle}&deg; corner, so the scan just missed the last stretch into it. Add the corner, or rescan that side.`
                      : ` - squaring off the two walls that reach it closes the room cleanly. That is what a corner blocked by furniture looks like. Add it, or rescan that side.`)
                  : ` - a wall may be missing. Add the suggested wall, or rescan that side.`) });
      }
      // EL ASISTENTE DE ESQUINAS: lo que no se cerró solo se PROPONE aquí,
      // con la cifra en el botón. Cada esquina tiene su propio "verificado"
      // (por llave), para que callar una no calle las demás del cuarto.
      const acks = room._cornerAcks || {};
      fpCornerFindings(data, idx).filter(f => f.band === 'propose' && !acks[f.key]).forEach(f => {
        const fi = fpFeetInches;
        if(f.kind === 'corner'){
          const lA = Math.hypot(f.wallA.end.x - f.wallA.start.x, f.wallA.end.y - f.wallA.start.y);
          const lB = Math.hypot(f.wallB.end.x - f.wallB.start.x, f.wallB.end.y - f.wallB.start.y);
          issues.push({ kind: 'corner', room: idx, ack: '_cornerAcks', ackKey: f.key, esquina: f,
            text: `${esc(roomName)}: the corner between the ${fi(lA)} wall and the ${fi(lB)} wall did not close - the outline cuts it diagonally, shortening the perimeter by ${fi(f.perimDeltaFt)} (about ${f.floorDeltaSqFt} sq ft of floor). The two walls meet ${fi(f.legA)} + ${fi(f.legB)} further on.${f.fromScan ? ' Flagged on site; not rescanned.' : ''}` });
        }else if(f.kind === 'skew'){
          const lE = Math.hypot(f.wall.end.x - f.wall.start.x, f.wall.end.y - f.wall.start.y);
          issues.push({ kind: 'skew', room: idx, ack: '_cornerAcks', ackKey: f.key, esquina: f,
            text: `${esc(roomName)}: the ${fi(lE)} wall is ${f.skewDeg}&deg; out of square with the ${fi(f.vecinoLen)} wall it meets - the corner sits ${fi(f.lateralFt)} off the line, in a room that is otherwise square.` });
        }else if(f.kind === 'overshoot'){
          issues.push({ kind: 'overshoot', room: idx, ack: '_cornerAcks', ackKey: f.key, esquina: f,
            text: `${esc(roomName)}: two walls cross ${fi(Math.max(f.sobraA, f.sobraB))} past their corner.` });
        }
      });
    });
    // OUR OWN CHECK, not Apple's: two rooms cannot both own the same
    // floor. When their outlines overlap, the building total adds that
    // floor twice. Found 51.0 sq ft of it on the real house - a sheet
    // printing 677.5 where the honest figure is about 626.5.
    //
    // The total is NOT quietly corrected here. That number gets billed
    // from, and the overlap means the OUTLINES are wrong; silently
    // subtracting would hide the defect and leave the drawing wrong
    // forever. He is shown the error and the honest figure, and fixes
    // the outline.
    const multiLv = floorplanLevels(data).length > 1;
    const lvNow = floorplanSelectedLevel;
    const onLv = r => !multiLv || (r.level||1) === lvNow;
    if(!data._overlapReviewed){
      const ov = fpRoomsOverlapSqFt(data, onLv);
      if(ov.pairs.length){
        const worst = ov.pairs.slice().sort((a,b) => b.sqFt - a.sqFt)[0];
        const shown = fpDisplayTotalAreaSqFt(data);
        issues.push({ kind: 'overlap', room: -1, ack: '_overlapReviewed',
          text: `${esc(worst.a)} and ${esc(worst.b)} both claim ${worst.sqFt} sq ft of the same floor`
            + (ov.pairs.length > 1 ? ` (${ov.pairs.length} pairs overlap, ${ov.sqFt} sq ft in all)` : '')
            + ` - the total counts it twice. It prints ${shown.toFixed(1)}; the honest figure is about ${(shown - ov.sqFt).toFixed(1)}. Fix the outline of one of them.` });
      }
    }
    // La puerta que un cuarto dibujo y el vecino no.
    fpMirroredPortCheck(data, multiLv ? lvNow : null).slice(0, 3).forEach(m => {
      issues.push({ kind: 'mirrored-port', room: m.missingIdx, mirror: m,
        text: `${esc(m.fromRoom)} has a ${fpFeetInches(m.widthFt)} ${m.kind === 'doors' ? 'door' : 'passage'} on the wall it shares with ${esc(m.missingIn)}, but ${esc(m.missingIn)} shows solid wall there. It is the same opening seen from one side only.` });
    });
    // Same idea: a wall running through another room's OPEN floor is a
    // contradiction - a shared wall lies on the boundary of both, never
    // inside one. (The boundary distance test matters: without it this
    // accused 11 perfectly good shared walls on the real house.)
    // Nuestra evidencia fisica contra la geometria: nadie atraviesa una
    // pared. Si el camino la cruza lejos de una puerta, o la pared no
    // esta donde dice, o el rastreo se corrio en ese tramo.
    fpPathCrossesWalls(data, multiLv ? lvNow : null).slice(0, 3).forEach(h => {
      issues.push({ kind: 'walked-through', room: -1,
        text: `${esc(h.room)}: the walk-through path goes straight through a ${fpFeetInches(h.lengthFt)} wall with no door there - that wall is in the wrong place, or tracking drifted. Check it in person.` });
    });
    fpWallsInsideOtherRooms(data, onLv).slice(0, 3).forEach(h => {
      issues.push({ kind: 'wallinside', room: -1,
        text: `${esc(h.room)}: a wall runs through ${esc(h.inside)}'s open floor - one of those two outlines is wrong.` });
    });
    // Coverage downgrades from the walkthrough inspection: elements the
    // camera never got a good look at. Capped so a rushed scan doesn't
    // flood the panel - the count still tells the honest story.
    const coverageIssues = [];
    Object.values(fpInspectionById).forEach(el => {
      if(el.observed !== 'poor') return;
      const room = ((data && data.rooms)||[])[el.roomIndex];
      if(!room || room.deleted) return;
      // "Check it in person" needs an end state - once the tech verifies
      // the room on site, its coverage flags are answered (same ack
      // pattern as low-confidence walls), and the quality badge becomes
      // reachable instead of nagging forever.
      if(room._coverageReviewed) return;
      const roomName = room.roomName || `Room ${el.roomIndex+1}`;
      const typeLabel = {wall:'wall', door:'door', window:'window', opening:'passage'}[el.type] || el.type;
      // Say WHY, with the number that actually drove the verdict. The
      // tier comes from how much of the element the camera covered, not
      // from how many camera positions it turned up in - so the old
      // wording ("not well observed... seen in 12 views") read as a
      // contradiction on a document an adjuster sees, and taught the
      // tech to distrust the whole review list.
      const cov = (typeof el.coverage === 'number') ? Math.round(el.coverage * 100) : null;
      const views = +el.views || 0;
      let why;
      if(views <= 1) why = `the camera only caught this ${typeLabel} from one spot`;
      else if(cov != null) why = `the camera covered only about ${cov}% of this ${typeLabel}, even though it shows up in ${views} views`;
      else why = `the camera never got a good look at this ${typeLabel}`;
      coverageIssues.push({ kind: 'coverage', room: el.roomIndex, kfId: el.bestKeyframe || null, ack: '_coverageReviewed',
        text: `${esc(roomName)}: ${why} - check it in person.` });
    });
    coverageIssues.slice(0, 6).forEach(it => issues.push(it));
    if(coverageIssues.length > 6) issues.push({ kind: 'coverage-more', room: -1, text: `${coverageIssues.length - 6} more elements had poor camera coverage - a slower walkthrough with the camera pointed at the walls covers them.` });
    fpStudIssues(data).forEach(it => issues.push(it));
    ((data && data.rooms) || []).forEach((room, idx) => {
      if(room && !room.deleted && room._studSplitNeedsMoistureReview)
        issues.push({ kind: 'studmoisture', room: idx, ack: '_studSplitNeedsMoistureReview',
          text: `${esc(room.roomName || `Room ${idx + 1}`)} was split along an open stud partition: the moisture map drawn before the split covers only this half. Check the moisture map on both halves.` });
    });
    return issues;
  }
  function floorplanWallEffectiveLength(w){
    return w._lengthOverrideFt != null ? w._lengthOverrideFt : w.lengthFt;
  }
  function floorplanOpeningEffectiveWidth(o){ return o._widthOverrideFt != null ? o._widthOverrideFt : o.widthFt; }
  function floorplanOpeningEffectiveHeight(o){ return o._heightOverrideFt != null ? o._heightOverrideFt : o.heightFt; }
  function fpAiOpeningOnBridge(data, seg, level){
    const mx = (seg.a.x+seg.b.x)/2, my = (seg.a.y+seg.b.y)/2;
    const half = seg.d/2 + 0.8;
    // Same-floor doors only: a level-2 doorway two stories up must not
    // veto closing a level-1 break (coordinates overlap across floors).
    return (data.rooms||[]).some(r => !r.deleted && (level == null || (r.level||1) === level) &&
      [].concat(r.doors||[], r.openings||[]).some(o => o.position && !o._removed &&
        Math.hypot(o.position.x-mx, o.position.y-my) <= half));
  }
  function fpAiFragileOutline(room){
    const poly = fpOrderedRoomPolygon(room);
    if(!poly || poly.length < 3) return true;
    for(let i=0;i<poly.length;i++) for(let j=i+1;j<poly.length;j++){
      if(Math.hypot(poly[i].x-poly[j].x, poly[i].y-poly[j].y) < 0.05) return true;
    }
    return false;
  }
  function fpOutlineDoublesBack(room){
    const poly = fpOrderedRoomPolygon(room);
    if(!poly || poly.length < 4) return false;
    const n = poly.length;
    for(let i=0;i<n;i++){
      const a = poly[(i-1+n)%n], b = poly[i], c = poly[(i+1)%n];
      const ux = b.x-a.x, uy = b.y-a.y, vx = c.x-b.x, vy = c.y-b.y;
      const lu = Math.hypot(ux,uy), lv = Math.hypot(vx,vy);
      if(lu < 0.3 || lv < 0.3) continue;
      if((ux*vx + uy*vy)/(lu*lv) <= -0.98) return true;   // turns back on itself
    }
    return false;
  }
  function fpAiSegmentCoveredByOtherWalls(work, ownRi, seg, level){
    const vx = seg.b.x - seg.a.x, vy = seg.b.y - seg.a.y;
    const L = Math.hypot(vx, vy) || 1;
    const ux = vx/L, uy = vy/L, nx = -uy, ny = ux;
    const spans = [];
    (work.rooms||[]).forEach((r, ri2) => {
      if(r.deleted || (level != null && (r.level||1) !== level)) return;
      (r.walls||[]).forEach(w => {
        if(!w.start || !w.end || w._added) return;
        const dx = w.end.x-w.start.x, dy = w.end.y-w.start.y;
        const wl = Math.hypot(dx, dy) || 1;
        if(Math.abs((dx/wl)*ux + (dy/wl)*uy) < 0.95) return;
        const offA = (w.start.x-seg.a.x)*nx + (w.start.y-seg.a.y)*ny;
        const offB = (w.end.x-seg.a.x)*nx + (w.end.y-seg.a.y)*ny;
        if(Math.abs(offA) > 0.8 || Math.abs(offB) > 0.8) return;
        const t0 = (w.start.x-seg.a.x)*ux + (w.start.y-seg.a.y)*uy;
        const t1 = (w.end.x-seg.a.x)*ux + (w.end.y-seg.a.y)*uy;
        const lo = Math.max(0, Math.min(t0,t1)), hi = Math.min(L, Math.max(t0,t1));
        if(hi > lo) spans.push([lo, hi]);
      });
    });
    spans.sort((a,b) => a[0]-b[0]);
    let covered = 0, cursor = 0;
    spans.forEach(([lo,hi]) => {
      if(hi > cursor){ covered += hi - Math.max(lo, cursor); cursor = Math.max(cursor, hi); }
    });
    return covered >= L * 0.7;
  }
  function floorplanRoomBounds(room){
    let minX=Infinity, maxX=-Infinity, minY=Infinity, maxY=-Infinity;
    // Malformed records (a wall missing an endpoint, an object with no
    // center) are skipped, never crashed on - adversarial testing showed
    // one bad record aborting whole passes through this function.
    const consider = p => { if(!p) return; minX=Math.min(minX,p.x); maxX=Math.max(maxX,p.x); minY=Math.min(minY,p.y); maxY=Math.max(maxY,p.y); };
    (room.walls||[]).forEach(w => { consider(w.start); consider(w.end); });
    (room.objects||[]).forEach(o => consider(o && o.center));
    return {minX, maxX, minY, maxY};
  }
  function floorplanRoomCentroid(room){
    const walls = room.walls || [];
    if(!walls.length) return {x:0, y:0};
    let sx=0, sy=0;
    walls.forEach(w => { sx += w.start.x; sy += w.start.y; });
    return { x: sx/walls.length, y: sy/walls.length };
  }
  function fpPointInPolygon(pt, poly){
    let inside = false;
    for(let i=0, j=poly.length-1; i<poly.length; j=i++){
      const xi=poly[i].x, yi=poly[i].y, xj=poly[j].x, yj=poly[j].y;
      const intersect = ((yi>pt.y) !== (yj>pt.y)) && (pt.x < (xj-xi)*(pt.y-yi)/(yj-yi)+xi);
      if(intersect) inside = !inside;
    }
    return inside;
  }
  function fpOrderedRoomPolygon(room, gapInfo){
    // Una pared de solo studs DIBUJADA Y NO PARTIDA (sin pareja) no es borde:
    // si entrara, el encadenado la cosería al anillo y la hoja imprimiría un
    // cuarto en ocho con piso y pared falsos - sin que nadie partiera nada.
    // Las particiones ya partidas (con _studPairId) sí son borde de su mitad.
    const walls = (room.walls||[]).filter(w => w.start && w.end && !(w._studWall && !w._studPairId)
      && Math.hypot(w.end.x-w.start.x, w.end.y-w.start.y) > 0.05);
    if(walls.length < 3) return walls.map(w => w.start);
    const tol = 1.0;
    const used = new Array(walls.length).fill(false);
    const chains = [];
    for(let s=0; s<walls.length; s++){
      if(used[s]) continue;
      used[s] = true;
      const chain = [{x:walls[s].start.x,y:walls[s].start.y},{x:walls[s].end.x,y:walls[s].end.y}];
      let extended = true;
      while(extended){
        extended = false;
        const head = chain[0], tail = chain[chain.length-1];
        let best = null;
        for(let i=0; i<walls.length; i++){
          if(used[i]) continue;
          const cands = [
            {d:Math.hypot(walls[i].start.x-tail.x,walls[i].start.y-tail.y), far:walls[i].end, atTail:true, i},
            {d:Math.hypot(walls[i].end.x-tail.x,walls[i].end.y-tail.y), far:walls[i].start, atTail:true, i},
            {d:Math.hypot(walls[i].start.x-head.x,walls[i].start.y-head.y), far:walls[i].end, atTail:false, i},
            {d:Math.hypot(walls[i].end.x-head.x,walls[i].end.y-head.y), far:walls[i].start, atTail:false, i},
          ];
          for(const c of cands) if(!best || c.d < best.d) best = c;
        }
        if(best && best.d <= tol){
          used[best.i] = true;
          if(best.atTail) chain.push({x:best.far.x,y:best.far.y});
          else chain.unshift({x:best.far.x,y:best.far.y});
          extended = true;
        }
      }
      chains.push(chain);
    }
    const chainLen = c => c.reduce((a,p,i)=> i ? a+Math.hypot(p.x-c[i-1].x,p.y-c[i-1].y) : 0, 0);
    let kept = chains.filter(c => chainLen(c) >= 2.5);
    if(!kept.length) kept = chains;
    kept.sort((a,b) => chainLen(b)-chainLen(a));
    const poly = kept[0].map(p => ({x:p.x,y:p.y}));
    const rest = kept.slice(1);
    while(rest.length){
      // THE root cause of the "grey shadows" and of the app asking the
      // tech to name his own bedroom. If what has been chained so far
      // ALREADY closes, it is the room's outline - full stop. Whatever
      // chain is left over is an INTERIOR wall of that room, not a piece
      // of its boundary, and bridging back out to it draws a figure
      // eight across the room's own floor. On the real Master Bedroom the
      // ring closed cleanly at 8 walls and the loop then bridged 15.5 ft
      // back to the closet's mouth wall and 19.2 ft home again, which
      // made an even-odd point test answer "outside" for most of the
      // bedroom. A leftover is NOT a gap - it is reported separately so
      // AI Fix never proposes a wall to close something that is closed.
      if(poly.length >= 3 &&
         Math.hypot(poly[0].x-poly[poly.length-1].x, poly[0].y-poly[poly.length-1].y) <= tol){
        if(gapInfo) gapInfo.leftovers = rest.map(c => c.map(pt => ({x:pt.x, y:pt.y})));
        break;
      }
      const tail = poly[poly.length-1];
      let bi=-1, bflip=false, bd=Infinity;
      rest.forEach((c,i) => {
        const dS = Math.hypot(c[0].x-tail.x, c[0].y-tail.y);
        const dE = Math.hypot(c[c.length-1].x-tail.x, c[c.length-1].y-tail.y);
        if(dS < bd){ bd=dS; bi=i; bflip=false; }
        if(dE < bd){ bd=dE; bi=i; bflip=true; }
      });
      const c = rest.splice(bi,1)[0];
      const seg = bflip ? c.slice().reverse() : c;
      // Bridged distances are reported to the caller (validation uses
      // them: a doorway-sized bridge is normal, a huge one means a wall
      // the scan probably missed). The bridge's actual endpoints ride
      // along so the review panel can OFFER the missing wall instead of
      // only describing it.
      if(gapInfo && bd > tol){
        gapInfo.bridges = (gapInfo.bridges||[]).concat(bd);
        (gapInfo.bridgeSegs = gapInfo.bridgeSegs||[]).push({ a:{x:tail.x,y:tail.y}, b:{x:seg[0].x,y:seg[0].y}, d:bd });
      }
      seg.forEach((p,i) => { if(i===0 && bd<=tol) return; poly.push({x:p.x,y:p.y}); });
    }
    const closeDist = Math.hypot(poly[0].x-poly[poly.length-1].x, poly[0].y-poly[poly.length-1].y);
    if(gapInfo && closeDist > tol){
      gapInfo.bridges = (gapInfo.bridges||[]).concat(closeDist);
      (gapInfo.bridgeSegs = gapInfo.bridgeSegs||[]).push({ a:{x:poly[poly.length-1].x,y:poly[poly.length-1].y}, b:{x:poly[0].x,y:poly[0].y}, d:closeDist });
    }
    if(poly.length>3 && closeDist <= tol) poly.pop();
    if(poly.length>=3) return fpPruneOutlineSpikes(poly);
    return walls.map(w=>w.start);
  }
  function fpPruneOutlineSpikes(poly){
    if(!poly || poly.length < 3) return poly;
    let pts = poly.slice(), changed = true, guard = 0;
    // UNA sola convergencia: quitar una espina puede dejar un lado de
    // largo cero y viceversa, asi que se repite hasta que no cambie nada.
    // Corriendo las dos podas por separado el duplicado sobrevivia (la de
    // largo cero corria antes y el bucle de espinas lo creaba despues).
    while(changed && pts.length >= 3 && guard++ < 64){
      changed = false;
      for(let i = 0; i < pts.length; i++){
        const a = pts[(i-1+pts.length)%pts.length], b = pts[i], c = pts[(i+1)%pts.length];
        // (1) LADO DE LARGO CERO. El contorno del Hallway y del Bathroom
        // reales vuelven a listar su primer vertice al final. No cambia el
        // area (la formula del zapatero lo ignora), pero
        // fpAiFragileOutline lee CUALQUIER par de vertices a menos de 0.05
        // pies como "figura de ocho" y declara el cuarto fragil. Un cuarto
        // fragil pierde su forma y pasa a reclamar su CAJA, y una caja se
        // traga lo que tenga al lado: asi desaparecio un closet real de
        // 8'0" x 1'6" del detector de huecos, y AI Fix llego a decir
        // "every space labeled" con un espacio sin nombre en el plano.
        if(pts.length > 3 && Math.hypot(b.x-c.x, b.y-c.y) < 0.02){ pts.splice(i, 1); changed = true; break; }
        // (2) ESPINA. El encadenado consume paredes ENTERAS y no puede
        // partir una, asi que cuando una pared se extiende mas alla del
        // cuarto (la del Bathroom real mide 16.07 pies y solo 7.37 bordean
        // el cuarto) el contorno sale hasta la punta y se devuelve por
        // encima de si mismo. Esa excursion encierra casi nada -- 1.8
        // pies cuadrados, por eso la validacion por AREA nunca pudo verla
        // -- pero aportaba 17.4 de los 42.2 pies de perimetro: el 41%.
        if(pts.length < 4) continue;
        const ax = b.x-a.x, ay = b.y-a.y, cx = c.x-b.x, cy = c.y-b.y;
        const la = Math.hypot(ax, ay), lc = Math.hypot(cx, cy);
        if(la < 1e-6 || lc < 1e-6) continue;
        if((ax*cx + ay*cy) / (la*lc) <= -0.98){ pts.splice(i, 1); changed = true; break; }
      }
    }
    return pts.length >= 3 ? pts : poly;
  }
  function fpPolygonAreaSqFt(poly){
    if(!poly || poly.length < 3) return 0;
    let area = 0;
    for(let i=0, j=poly.length-1; i<poly.length; j=i++) area += poly[j].x*poly[i].y - poly[i].x*poly[j].y;
    return Math.abs(area/2);
  }
  function fpRoomDisplayAreaSqFt(room){
    const area = fpPolygonAreaSqFt(fpOrderedRoomPolygon(room));
    if(area > 1) return Math.round(area*10)/10;
    return ((room.summary && room.summary.floorAreaSqFt) || 0);
  }
  function fpDisplayTotalAreaSqFt(data){
    return Math.round(((data && data.rooms) || []).reduce((sum, r) => r.deleted ? sum : sum + fpRoomDisplayAreaSqFt(r), 0)*10)/10;
  }
  function fpDistToPolygon(pt, poly){
    let best = Infinity;
    for(let i = 0, j = poly.length - 1; i < poly.length; j = i++){
      const a = poly[j], b = poly[i];
      const dx = b.x - a.x, dy = b.y - a.y, L = dx*dx + dy*dy;
      let t = L ? ((pt.x-a.x)*dx + (pt.y-a.y)*dy) / L : 0;
      t = Math.max(0, Math.min(1, t));
      best = Math.min(best, Math.hypot(pt.x - (a.x + t*dx), pt.y - (a.y + t*dy)));
    }
    return best;
  }
  function fpRoomMeasurements(room){
    const gi = {};
    const poly = fpOrderedRoomPolygon(room, gi);
    // Con menos de 3 vertices no hay contorno: el lazo de abajo recorreria
    // los mismos 2 puntos de ida y vuelta y publicaria el DOBLE de una
    // pared como si fuera el perimetro del cuarto.
    const outlineOk = poly.length >= 3;
    let perimeterFt = 0;
    for(let i = 0, j = poly.length - 1; i < poly.length; j = i++)
      perimeterFt += Math.hypot(poly[i].x - poly[j].x, poly[i].y - poly[j].y);
    const bins = {};
    (room.walls||[]).forEach(w => {
      const h = Math.round((w.heightFt||0) * 20) / 20;
      if(h > 0) bins[h] = (bins[h]||0) + floorplanWallEffectiveLength(w);
    });
    const ranked = Object.entries(bins).sort((a, b) => b[1] - a[1]);
    const wallHeightFt = ranked.length ? parseFloat(ranked[0][0]) : 0;
    // Media pulgada de diferencia es ruido de escaneo; medio pie es otra
    // pared. Solo lo segundo se reporta.
    const oddHeights = ranked.slice(1)
      .filter(e => Math.abs(parseFloat(e[0]) - wallHeightFt) > 0.5)
      .map(e => ({ heightFt: parseFloat(e[0]), lengthFt: e[1] }));
    // Puertas y ventanas se restan de la pared bruta. Las puertas y los
    // pasos ADEMAS cortan el rodapie; una ventana no.
    let openingSqFt = 0, doorWidthFt = 0, insideOpenings = 0;
    [['doors', true], ['windows', false], ['openings', true]].forEach(([k, cutsBase]) => {
      (room[k]||[]).forEach(o => {
        if(o._removed) return;
        // Una abertura reclasificada a mano cuenta como lo que el tecnico
        // dijo que es, no como la lista donde quedo guardada.
        const kind = o._kindOverride || (k === 'windows' ? 'window' : k === 'doors' ? 'door' : 'opening');
        const w = o._widthOverrideFt != null ? o._widthOverrideFt : (o.widthFt || 0);
        const h = o._heightOverrideFt != null ? o._heightOverrideFt : (o.heightFt || 0);
        // Se pregunta si la PARED de la abertura está en el contorno, no si la
        // abertura misma está cerca: una puerta de una pared perpendicular a
        // medio pie de una partición no es de la partición.
        const wDe = o.wallId != null ? (room.walls||[]).find(w => String(w.id) === String(o.wallId) && w.start && w.end) : null;
        const ptRef = wDe ? { x: (wDe.start.x + wDe.end.x) / 2, y: (wDe.start.y + wDe.end.y) / 2 } : o.position;
        if(ptRef && poly.length >= 3 && fpDistToPolygon(ptRef, poly) > 0.5){
          insideOpenings++;   // en una particion interior: el perimetro no la incluye
          return;
        }
        openingSqFt += w * h;
        if(kind !== 'window') doorWidthFt += w;
      });
    });
    const grossWallSqFt = perimeterFt * wallHeightFt;
    const floorSqFt = fpRoomDisplayAreaSqFt(room);
    return {
      floorSqFt, outlineOk,
      // Un techo PLANO a una sola altura. El escaneo no entrega geometria
      // de techo, asi que un techo inclinado o abovedado no se detecta -
      // por eso la hoja lo dice en letra, en vez de dejarlo suponer.
      ceilingSqFt: floorSqFt,
      perimeterFt,
      baseboardFt: Math.max(0, perimeterFt - doorWidthFt),
      wallHeightFt, oddHeights,
      // Sin altura no hay pared que calcular. Se DECLARA, porque 0.0 en
      // una columna de medidas se lee como "este cuarto no tiene pared",
      // que es una mentira distinta de "no lo sabemos".
      heightKnown: wallHeightFt > 0,
      // Aberturas en paredes interiores (un divisor de closet): ni su area
      // ni su ancho tocan estas cifras, porque el perimetro tampoco
      // incluye esa pared. Se cuentan para poder decirlo.
      insideOpenings,
      grossWallSqFt, openingSqFt,
      netWallSqFt: Math.max(0, grossWallSqFt - openingSqFt),
      // Pies del borde que la app cerro sola. Todo lo que se calcula
      // sobre ese tramo -- perimetro, pared, rodapie -- hereda la duda,
      // asi que viaja con el resultado en vez de perderse.
      guessedFt: (gi.bridgeSegs||[]).reduce((t, b) => t + (b && b.d > 1 ? b.d : 0), 0)
    };
  }
  function fpLadoDeLinea(p, a, b){
    const vx = b.x - a.x, vy = b.y - a.y, L = Math.hypot(vx, vy) || 1;
    return ((p.x - a.x) * -vy + (p.y - a.y) * vx) / L;
  }
  function fpCutRoomByLine(room, a, b){
    const poly = fpOrderedRoomPolygon(room);
    if(!poly || poly.length < 3) return { error: 'el cuarto no tiene un contorno cerrado que partir' };
    const EPS = 0.05;
    const d = poly.map(p => fpLadoDeLinea(p, a, b));
    // Los cruces de la recta con el contorno. Tienen que ser EXACTAMENTE dos:
    // con dos, el cuarto queda en dos pedazos y nada más; con cuatro (una U)
    // quedaría en tres y una cara se perdería. Es el candado 6.
    const cruces = [];
    for(let i = 0; i < poly.length; i++){
      const j = (i + 1) % poly.length, di = d[i], dj = d[j];
      if((di > EPS && dj < -EPS) || (di < -EPS && dj > EPS)){
        const t = di / (di - dj);
        cruces.push({ x: poly[i].x + (poly[j].x - poly[i].x) * t, y: poly[i].y + (poly[j].y - poly[i].y) * t });
      }
    }
    if(cruces.length < 2) return { error: 'la línea no atraviesa el cuarto de lado a lado; muévela para que toque las dos paredes' };
    if(cruces.length > 2) return { error: 'la línea cruza el contorno ' + cruces.length + ' veces y partiría el cuarto en más de dos; muévela a un tramo recto' };
    // UNA PARED DE STUDS LLEGA A LAS PAREDES A 90°. Una guía de un pie
    // dibujada con el dedo sale torcida casi siempre, y la recta infinita la
    // volvería una diagonal de pared a pared que se COBRA. Se busca el tramo
    // más largo del contorno que cruza y se gira la guía, sobre su punto
    // medio, hasta la perpendicular exacta de ese tramo. A más de 40° no se
    // adivina: se niega.
    let enderezadaDeg = 0;
    {
      let tramo = null;
      for(let i = 0; i < poly.length; i++){
        const j = (i + 1) % poly.length, di = d[i], dj = d[j];
        if((di > EPS && dj < -EPS) || (di < -EPS && dj > EPS)){
          const L = Math.hypot(poly[j].x - poly[i].x, poly[j].y - poly[i].y);
          if(!tramo || L > tramo.L) tramo = { L, ux: (poly[j].x - poly[i].x) / L, uy: (poly[j].y - poly[i].y) / L };
        }
      }
      if(tramo){
        const gx = b.x - a.x, gy = b.y - a.y, gL = Math.hypot(gx, gy) || 1;
        const px = -tramo.uy, py = tramo.ux;
        enderezadaDeg = Math.acos(Math.min(1, Math.abs((gx * px + gy * py) / gL))) * 180 / Math.PI;
        if(enderezadaDeg > 40) return { error: 'la línea sale torcida (' + Math.round(enderezadaDeg) + '° fuera de escuadra); dibújela derecha o de pared a pared' };
        if(enderezadaDeg > 0.01){
          const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
          a = { x: mid.x - px, y: mid.y - py }; b = { x: mid.x + px, y: mid.y + py };
          // Con la guía enderezada, los cruces se vuelven a calcular.
          cruces.length = 0;
          for(let i = 0; i < poly.length; i++){
            const j = (i + 1) % poly.length;
            const di = fpLadoDeLinea(poly[i], a, b), dj = fpLadoDeLinea(poly[j], a, b);
            if((di > EPS && dj < -EPS) || (di < -EPS && dj > EPS)){
              const t = di / (di - dj);
              cruces.push({ x: poly[i].x + (poly[j].x - poly[i].x) * t, y: poly[i].y + (poly[j].y - poly[i].y) * t });
            }
          }
          if(cruces.length !== 2) return { error: 'enderezada, la línea ya no parte el cuarto en dos; muévela' };
        }
      }
    }
    // Una partición YA PARTIDA (con pareja) que cruce la recta no se trunca:
    // truncar una sola copia dejaría a la otra mitad con la copia entera y la
    // pareja diría tres cuartos con un largo que no es. Se niega.
    const cruzaPareja = (room.walls||[]).some(w => w._studWall && w._studPairId && w.start && w.end
      && ((fpLadoDeLinea(w.start, a, b) > EPS && fpLadoDeLinea(w.end, a, b) < -EPS) || (fpLadoDeLinea(w.start, a, b) < -EPS && fpLadoDeLinea(w.end, a, b) > EPS)));
    if(cruzaPareja) return { error: 'la línea cruza una partición que ya partió otro cuarto; muévela' };
    // Una pared que ya esté SOBRE la línea no se duplica ni se borra callada.
    const yaHay = (room.walls||[]).some(w => w.start && w.end && !w._studWall
      && Math.abs(fpLadoDeLinea(w.start, a, b)) < 0.3 && Math.abs(fpLadoDeLinea(w.end, a, b)) < 0.3
      && Math.hypot(w.end.x - w.start.x, w.end.y - w.start.y) > 1);
    if(yaHay) return { error: 'ya hay una pared dibujada sobre esa línea; bórrela o mueva la línea' };
    const particion = { start: { x: FP_QUANT(cruces[0].x), y: FP_QUANT(cruces[0].y) },
                        end:   { x: FP_QUANT(cruces[1].x), y: FP_QUANT(cruces[1].y) } };
    const largo = Math.hypot(particion.end.x - particion.start.x, particion.end.y - particion.start.y);
    if(largo < 1) return { error: 'la pared saldría de menos de un pie' };
    // Cada pared a su lado (con la guía ya enderezada); la que cruza se trunca.
    const A = [], B = [], renombradas = {};
    (room.walls||[]).forEach(w => {
      if(!w.start || !w.end) return;
      // SOLO la guía sin partir se reemplaza por la partición. Una partición
      // ya partida (con pareja) es una pared como cualquiera: si se saltara,
      // partir dos veces borraría la primera de la mitad que toca.
      if(w._studWall && !w._studPairId) return;
      const ds = fpLadoDeLinea(w.start, a, b), de = fpLadoDeLinea(w.end, a, b);
      if(ds >= -EPS && de >= -EPS){ A.push(w); return; }
      if(ds <= EPS && de <= EPS){ B.push(w); return; }
      const t = ds / (ds - de);
      const c = { x: FP_QUANT(w.start.x + (w.end.x - w.start.x) * t), y: FP_QUANT(w.start.y + (w.end.y - w.start.y) * t) };
      const mk = (s0, e0) => {
        const x = Object.assign({}, w, { start: { x: s0.x, y: s0.y }, end: { x: e0.x, y: e0.y },
          lengthFt: Math.round(Math.hypot(e0.x - s0.x, e0.y - s0.y) * 100) / 100, _studSplitTruncated: true });
        // Una corrección de largo sobre una pared que ahora son dos no se
        // puede repartir: se suelta, y se deja dicho.
        if(x._lengthOverrideFt != null){ delete x._lengthOverrideFt; x._overrideDropped = true; }
        return x;
      };
      const ladoA = mk(ds >= 0 ? w.start : w.end, c), ladoB = mk(ds >= 0 ? w.end : w.start, c);
      // El pedazo más largo conserva el id: su entrada en el índice de
      // inspección (cobertura, mejor foto) se va con él.
      if(ladoB.lengthFt > ladoA.lengthFt) ladoA.id = fpNewId(); else ladoB.id = fpNewId();
      // Quien apunte a la pared vieja (una puerta, por wallId) tiene que
      // seguir a SU pedazo: aquí se anota a dónde fue cada uno.
      renombradas[String(w.id)] = { idA: ladoA.id, idB: ladoB.id };
      A.push(ladoA); B.push(ladoB);
    });
    return { A, B, particion, renombradas, largo: Math.round(largo * 100) / 100, cruces: cruces.length,
             enderezadaDeg: Math.round(enderezadaDeg * 10) / 10, a, b };
  }
  function fpStudSplitCandidates(data, roomIdx, a, b){
    const room = (data.rooms||[])[roomIdx];
    if(!room) return { error: 'no hay cuarto' };
    const cut = fpCutRoomByLine(room, a, b);
    if(cut.error) return cut;
    a = cut.a; b = cut.b;                       // la guía, ya enderezada
    const m0 = fpRoomMeasurements(room);
    const pairId = fpNewId();
    // La partición, una copia por mitad, con la MISMA pareja. Nunca un valor
    // nuevo en `confidence`: el dibujo solo entiende 'low'; la marca es una
    // llave booleana propia, como `_added`.
    const pared = () => {
      const w = { id: fpNewId(), start: { x: cut.particion.start.x, y: cut.particion.start.y },
                  end: { x: cut.particion.end.x, y: cut.particion.end.y }, lengthFt: cut.largo,
                  _added: true, _studWall: true, _studPairId: pairId };
      // El alto es el del cuarto, MEDIDO. Sin alto conocido no se escribe
      // ninguno: así la hoja declara "sin altura" en vez de inventar un 8.
      if(m0.heightKnown) w.heightFt = m0.wallHeightFt;
      return w;
    };
    const pA = pared(), pB = pared();
    const P0 = cut.particion.start, P1 = cut.particion.end;
    // Una abertura que va a la partición se PROYECTA sobre ella: así queda a
    // 0 pies del contorno de las dos mitades y las dos la descuentan, que es
    // lo físico (la puerta está en esa pared).
    const proyecta = pt => { const vx = P1.x - P0.x, vy = P1.y - P0.y, L2 = vx*vx + vy*vy || 1;
      const t = Math.max(0, Math.min(1, ((pt.x - P0.x)*vx + (pt.y - P0.y)*vy) / L2));
      return { x: FP_QUANT(P0.x + vx*t), y: FP_QUANT(P0.y + vy*t) }; };
    const colineal = w => w && w.start && w.end && Math.abs(fpLadoDeLinea(w.start, a, b)) < 0.3 && Math.abs(fpLadoDeLinea(w.end, a, b)) < 0.3;
    const reparte = (lista, key) => {
      const ra = [], rb = [];
      (lista||[]).forEach(o => {
        const pt = o && o[key];
        if(!pt){ ra.push(o); return; }
        const lado = fpLadoDeLinea(pt, a, b);
        if(key !== 'position'){ (lado >= 0 ? ra : rb).push(o); return; }
        // Una abertura va a las DOS mitades solo si está EN la pared de la
        // línea (la guía o una colineal), no por estar cerca: la puerta de
        // una pared perpendicular a medio pie de la línea es de UN lado.
        const wOf = o.wallId != null ? (room.walls||[]).find(w => String(w.id) === String(o.wallId)) : null;
        const enLaLinea = wOf ? ((wOf._studWall && !wOf._studPairId) || colineal(wOf)) : Math.abs(lado) < 0.25;
        if(enLaLinea){
          const pid = fpNewId(), pos = proyecta(pt);
          ra.push(Object.assign({}, o, { _pairId: pid, wallId: pA.id, position: { x: pos.x, y: pos.y } }));
          rb.push(Object.assign({}, o, { id: fpNewId(), _pairId: pid, wallId: pB.id, position: { x: pos.x, y: pos.y } }));
          return;
        }
        // Su pared se truncó: sigue al pedazo de su lado, con el id nuevo.
        const ren = wOf && cut.renombradas[String(wOf.id)];
        if(ren){ (lado >= 0 ? ra : rb).push(Object.assign({}, o, { wallId: lado >= 0 ? ren.idA : ren.idB })); return; }
        // Su pared quedó entera de un lado: va con ella, no por su propia distancia.
        if(wOf && wOf.start && wOf.end){
          const mid = fpLadoDeLinea({ x: (wOf.start.x + wOf.end.x)/2, y: (wOf.start.y + wOf.end.y)/2 }, a, b);
          (mid >= 0 ? ra : rb).push(o); return;
        }
        (lado >= 0 ? ra : rb).push(o);
      });
      return [ra, rb];
    };
    const [dA, dB] = reparte(room.doors, 'position');
    const [wA, wB] = reparte(room.windows, 'position');
    const [oA, oB] = reparte(room.openings, 'position');
    const [obA, obB] = reparte(room.objects, 'center');
    const roomA = Object.assign({}, room, { walls: cut.A.concat([pA]), doors: dA, windows: wA, openings: oA,
      objects: obA });
    delete roomA._subAreas;          // se vuelven a detectar sobre la mitad
    // La mitad nueva: sin equipo (copiarlo imprimiría los air movers dos
    // veces), sin nombre todavía, y con la marca de dónde salió.
    const roomB = { roomName: '', level: room.level || 1, walls: cut.B.concat([pB]), doors: dB, windows: wB,
      openings: oB, objects: obB, summary: {}, _studSplitFrom: roomIdx };
    return { roomA, roomB, cut, m0 };
  }
  function fpStudSplitSanity(antes, A, B, largo, cruces){
    const fail = [];
    const corto = r => { const bb = floorplanRoomBounds(r); return Math.min(bb.maxX - bb.minX, bb.maxY - bb.minY); };
    const forma = m => m.floorSqFt > 0 ? m.perimeterFt / Math.sqrt(m.floorSqFt) : Infinity;
    const n1 = v => (Math.round(v * 10) / 10).toFixed(1);
    if(cruces !== 2) fail.push('la línea tiene que cruzar el contorno exactamente dos veces');
    if(!A.m.outlineOk || !B.m.outlineOk) fail.push('una de las mitades no cierra');
    if(!(A.m.floorSqFt >= 5 && B.m.floorSqFt >= 5)) fail.push('una mitad quedaría de menos de 5 pies cuadrados');
    if(!(corto(A.room) >= 1.8 && corto(B.room) >= 1.8)) fail.push('una mitad quedaría más angosta que 1 pie 10 pulgadas');
    // Los 10 cuartos reales del repo van de 4.0 a 6.1; un corte malo mide 24.
    if(forma(A.m) > 8 || forma(B.m) > 8) fail.push('una mitad quedaría con una forma que no es de cuarto (muy larga y angosta)');
    // LEY DE CONSERVACIÓN 1: el piso no puede cambiar.
    const piso = antes.m.floorSqFt, pisoDespues = A.m.floorSqFt + B.m.floorSqFt;
    if(Math.abs(pisoDespues - piso) > Math.max(0.5, piso * 0.03))
      fail.push('el piso no se conserva (' + n1(piso) + ' antes, ' + n1(pisoDespues) + ' después)');
    // LEY DE CONSERVACIÓN 2: la partición tiene exactamente dos caras. Si sale
    // menos, una mitad cerró su anillo antes de tiempo y solo se cobra UNA
    // cara — el corte que dos jueces midieron sobre la casa real.
    const perim = antes.m.perimeterFt + 2 * largo, perimDespues = A.m.perimeterFt + B.m.perimeterFt;
    if(Math.abs(perimDespues - perim) > 0.5)
      fail.push('el perímetro no cuadra: las dos caras de la partición no salen enteras (' + n1(perimDespues) + ' en vez de ' + n1(perim) + ')');
    // CANDADO 7: el corte no puede dejar un tramo que la app cierre sola.
    if((A.m.guessedFt||0) + (B.m.guessedFt||0) > (antes.m.guessedFt||0) + 0.5)
      fail.push('una mitad quedaría con un tramo que la app cerraría sola, no medido');
    return { ok: !fail.length, fail };
  }
  function fpPlanMeasurements(data, onLevel){
    const t = { rooms: 0, floorSqFt: 0, ceilingSqFt: 0, perimeterFt: 0, baseboardFt: 0,
                grossWallSqFt: 0, openingSqFt: 0, netWallSqFt: 0, guessedFt: 0, guessedRooms: 0,
                odd: [], noHeight: [], noOutline: [], insideOpenings: 0 };
    ((data && data.rooms) || []).forEach((r, i) => {
      if(r.deleted || !(r.walls||[]).length) return;
      if(onLevel && !onLevel(r)) return;
      const m = fpRoomMeasurements(r);
      t.rooms++;
      // Un cuarto sin contorno no aporta perimetro ni pared: sumar su
      // numero inventado contaminaria el TOTAL de toda la casa.
      const keys = m.outlineOk
        ? ['floorSqFt','ceilingSqFt','perimeterFt','baseboardFt','grossWallSqFt','openingSqFt','netWallSqFt','guessedFt']
        : ['floorSqFt','ceilingSqFt'];
      keys.forEach(k => { t[k] += m[k]; });
      if(m.guessedFt > 1) t.guessedRooms++;
      if(m.oddHeights.length) t.odd.push({ idx: i, room: r, m });
      // Un cuarto sin altura no aporta pared, y el TOTAL lo estaria
      // soltando en silencio: se guarda para decirlo.
      if(!m.heightKnown) t.noHeight.push({ idx: i, room: r });
      if(!m.outlineOk) t.noOutline.push({ idx: i, room: r });
      if(m.insideOpenings) t.insideOpenings += m.insideOpenings;
    });
    return t;
  }
  function fpObjectClearance(pt, room){
    let clear = Infinity;
    (room.objects||[]).forEach(o => {
      if(o._hidden || !o.center) return;
      const ddx = Math.max(Math.abs(pt.x-o.center.x) - (o.widthFt||1)/2, 0);
      const ddy = Math.max(Math.abs(pt.y-o.center.y) - (o.depthFt||1)/2, 0);
      clear = Math.min(clear, Math.hypot(ddx, ddy));
    });
    return clear;
  }
  function floorplanLabelAnchor(room){
    const poly = fpOrderedRoomPolygon(room);
    if(poly.length < 3) return floorplanRoomCentroid(room);
    let area=0, cx=0, cy=0;
    for(let i=0, j=poly.length-1; i<poly.length; j=i++){
      const cross = poly[j].x*poly[i].y - poly[i].x*poly[j].y;
      area += cross; cx += (poly[j].x+poly[i].x)*cross; cy += (poly[j].y+poly[i].y)*cross;
    }
    area *= 0.5;
    if(Math.abs(area) < 1e-6) return floorplanRoomCentroid(room);
    const centroid = { x: cx/(6*area), y: cy/(6*area) };
    if(fpPointInPolygon(centroid, poly) && fpObjectClearance(centroid, room) >= 1.0) return centroid;
    const b = floorplanRoomBounds(room);
    const wallDist = p => Math.min(...poly.map((v,i) => {
      const w2 = poly[(i+1)%poly.length];
      const dx=w2.x-v.x, dy=w2.y-v.y, len2=dx*dx+dy*dy || 1;
      const t = Math.max(0, Math.min(1, ((p.x-v.x)*dx+(p.y-v.y)*dy)/len2));
      return Math.hypot(p.x-(v.x+dx*t), p.y-(v.y+dy*t));
    }));
    let best = centroid, bestScore = -Infinity, bestInside = false;
    const steps = 16;
    for(let ix=0; ix<=steps; ix++){
      for(let iy=0; iy<=steps; iy++){
        const p = { x: b.minX + (b.maxX-b.minX)*ix/steps, y: b.minY + (b.maxY-b.minY)*iy/steps };
        if(!fpPointInPolygon(p, poly)) continue;
        // Clear space matters, but past ~1.5ft more clearance stops
        // helping (the label already fits) - capping it low keeps the
        // winner near the middle instead of hugging the emptiest corner,
        // while the wall-distance term (capped higher) and the pull
        // toward the centroid keep the placement central and
        // professional-looking.
        const score = Math.min(wallDist(p), 3) + Math.min(Math.max(fpObjectClearance(p, room), 0), 1.5)*1.2
          - Math.hypot(p.x-centroid.x, p.y-centroid.y)*0.15;
        if(score > bestScore){ bestScore = score; best = p; bestInside = true; }
      }
    }
    return bestInside ? best : centroid;
  }
  const FLOORPLAN_LABEL_LEARNING_KEY = 'floorplanLabelLearning';
  function fpLoadLabelLearning(){ return []; }
  function fpLearnedLabelBias(){
    const history = fpLoadLabelLearning();
    if(history.length < 3) return null;
    const sum = history.reduce((acc,h) => ({ normDx: acc.normDx+h.normDx, normDy: acc.normDy+h.normDy }), {normDx:0, normDy:0});
    return { normDx: sum.normDx/history.length, normDy: sum.normDy/history.length };
  }
  function floorplanSmartLabelAnchor(room){
    const anchor = floorplanLabelAnchor(room);
    const bias = fpLearnedLabelBias();
    if(!bias) return anchor;
    const b = floorplanRoomBounds(room);
    const biased = { x: anchor.x + bias.normDx*(b.maxX-b.minX), y: anchor.y + bias.normDy*(b.maxY-b.minY) };
    const poly = fpOrderedRoomPolygon(room);
    return (poly.length >= 3 && fpPointInPolygon(biased, poly)) ? biased : anchor;
  }
  function floorplanBuildingCentroid(rooms){
    let sx=0, sy=0, n=0;
    (rooms||[]).forEach(r => (r.walls||[]).forEach(w => { sx+=w.start.x; sy+=w.start.y; n++; }));
    return n ? { x: sx/n, y: sy/n } : { x:0, y:0 };
  }
  function floorplanIsExteriorWall(wall, ownRoom, allRooms){
    if(!allRooms) return true; // unmerged/standalone view - every wall is its own room's exterior
    const dx = wall.end.x-wall.start.x, dy = wall.end.y-wall.start.y;
    const len = Math.hypot(dx,dy) || 1;
    const ux = dx/len, uy = dy/len;
    const nx = -uy, ny = ux; // unit normal to this wall's own line
    const perpTol = 0.6; // feet - how far off the same line still counts as "the same wall"
    const minOverlapFt = 1.0; // feet - a mere touching corner isn't a shared wall
    // floorplanLabelAnchor, not the naive vertex-average centroid: the
    // side-of-the-line test only works with a point that is genuinely
    // INSIDE the room, and the naive average can land outside a concave
    // L/U-shaped room - putting it on the wrong side and corrupting the
    // interior/exterior call for every wall of that room.
    const ownCentroid = floorplanLabelAnchor(ownRoom);
    for(const room of allRooms){
      if(room === ownRoom) continue;
      const matchCentroid = floorplanLabelAnchor(room);
      for(const w of (room.walls||[])){
        const wdx = w.end.x-w.start.x, wdy = w.end.y-w.start.y;
        const wlen = Math.hypot(wdx,wdy) || 1;
        const wux = wdx/wlen, wuy = wdy/wlen;
        if(Math.abs(ux*wux + uy*wuy) < 0.98) continue; // not parallel (or anti-parallel)
        const px = w.start.x-wall.start.x, py = w.start.y-wall.start.y;
        if(Math.abs(px*nx + py*ny) > perpTol) continue; // not on the same line
        const proj = p => (p.x-wall.start.x)*ux + (p.y-wall.start.y)*uy;
        const b0 = proj(w.start), b1 = proj(w.end);
        const lo = Math.max(0, Math.min(b0,b1)), hi = Math.min(len, Math.max(b0,b1));
        if(hi - lo <= minOverlapFt) continue; // not enough shared run to be the same wall
        const sideOwn = (ownCentroid.x-wall.start.x)*nx + (ownCentroid.y-wall.start.y)*ny;
        const sideMatch = (matchCentroid.x-wall.start.x)*nx + (matchCentroid.y-wall.start.y)*ny;
        // Ambiguous (a centroid landing exactly on the line) or same-side
        // matches don't prove a real partition - keep looking rather than
        // suppressing.
        if(sideOwn === 0 || sideMatch === 0 || (sideOwn > 0) === (sideMatch > 0)) continue;
        return false;
      }
    }
    return true;
  }
  const FLOORPLAN_SVG_SCALE = 55;
  function fpAnnotationLabelSvg(X, Y, cls, attrs, meta, cx, cy, name, w, d){
    const off = meta._offFt || {dx:0, dy:0};
    const k = Math.max(0.6, Math.min(2.4, meta._labelScale || 1));
    const sx = X(cx + (off.dx||0)), sy = Y(cy + (off.dy||0));
    const dim = (w > 0 && d > 0)
      ? `<text x="${sx}" y="${sy + 11*k}" font-size="${(15*k).toFixed(1)}" font-weight="700" font-family="'IBM Plex Mono',monospace" fill="#5a6472" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="4">${fpFeetInches(w)} x ${fpFeetInches(d)}</text>`
      : '';
    return `<g class="${cls}" ${attrs} style="cursor:grab;">`
      + `<text x="${sx}" y="${sy - 9*k}" font-size="${(17*k).toFixed(1)}" font-weight="700" letter-spacing="0.4" font-family="'IBM Plex Sans',sans-serif" fill="#3A4552" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="4">${esc(name).toUpperCase()}</text>`
      + dim + `</g>`;
  }
  const FLOORPLAN_WALL_THICKNESS_FT = 0.65;
  const FLOORPLAN_FLOOR_FILL = '#fbfbfa'; // plain, like a real CAD export - not a colored tint per room;
  function fpPerp(dx, dy){ const len = Math.sqrt(dx*dx+dy*dy) || 1; return { x: -dy/len, y: dx/len }; }
  function fpOpeningHitTarget(cls, roomIdx, id, o, wall, X, Y){
    const cx = X(o.position.x), cy = Y(o.position.y);
    if(wall && wall.start && wall.end){
      const dx = wall.end.x-wall.start.x, dy = wall.end.y-wall.start.y;
      const len = Math.hypot(dx, dy) || 1;
      const ux = dx/len, uy = dy/len;
      const half = Math.max(1.0, (floorplanOpeningEffectiveWidth(o) || 2.5)/2 + 0.3);
      return `<line class="${cls}" data-room-idx="${roomIdx}" data-opening-id="${id}" `
        + `x1="${X(o.position.x - ux*half)}" y1="${Y(o.position.y - uy*half)}" `
        + `x2="${X(o.position.x + ux*half)}" y2="${Y(o.position.y + uy*half)}" `
        + `stroke="transparent" stroke-width="34" stroke-linecap="round" style="pointer-events:stroke; cursor:pointer;"/>`;
    }
    return `<circle class="${cls}" data-room-idx="${roomIdx}" data-opening-id="${id}" cx="${cx}" cy="${cy}" r="20" fill="transparent" style="cursor:pointer;"/>`;
  }
  function fpPts(pts){ return pts.map(p => `${p.x},${p.y}`).join(' '); }
  function fpDefs(){
    return `<defs><pattern id="fpHatch" width="6" height="6" patternTransform="rotate(45)" patternUnits="userSpaceOnUse">`
      + `<rect width="6" height="6" fill="#e3e5e9"/><line x1="0" y1="0" x2="0" y2="6" stroke="#b7bcc4" stroke-width="1.4"/>`
      + `</pattern></defs>`;
  }
  function fpFeetInches(decimalFeet){
    const totalInches = Math.round(decimalFeet * 12);
    const feet = Math.floor(totalInches / 12);
    const inches = totalInches % 12;
    return `${feet}'-${inches}"`;
  }
  function fpWallOutwardNormal(wall, centroid, atPoint){
    const dx = wall.end.x - wall.start.x, dy = wall.end.y - wall.start.y;
    const len = Math.sqrt(dx*dx+dy*dy) || 1;
    let nx = -dy/len, ny = dx/len;
    const px = atPoint ? atPoint.x : (wall.start.x+wall.end.x)/2;
    const py = atPoint ? atPoint.y : (wall.start.y+wall.end.y)/2;
    const toCx = centroid.x - px, toCy = centroid.y - py;
    if(nx*toCx + ny*toCy > 0){ nx = -nx; ny = -ny; }
    return {x:nx, y:ny};
  }
  function fpDimensionLine(wall, centroid, X, Y, dimText){
    const n = fpWallOutwardNormal(wall, centroid);
    const nx = n.x, ny = n.y;
    const midX = (wall.start.x+wall.end.x)/2, midY = (wall.start.y+wall.end.y)/2;
    const off = 1.0, tick = 0.15;
    const a = { x: wall.start.x + nx*off, y: wall.start.y + ny*off };
    const b = { x: wall.end.x + nx*off, y: wall.end.y + ny*off };
    const P = pt => ({ x: X(pt.x), y: Y(pt.y) });
    const S = P(wall.start), E = P(wall.end), A = P(a), B = P(b);
    let s = '';
    s += `<line x1="${S.x}" y1="${S.y}" x2="${A.x}" y2="${A.y}" stroke="#aeb4bb" stroke-width="1"/>`;
    s += `<line x1="${E.x}" y1="${E.y}" x2="${B.x}" y2="${B.y}" stroke="#aeb4bb" stroke-width="1"/>`;
    s += `<line x1="${A.x}" y1="${A.y}" x2="${B.x}" y2="${B.y}" stroke="#5a636d" stroke-width="1.5"/>`;
    const endTick = (pt) => {
      const t1 = P({x:pt.x-nx*tick, y:pt.y-ny*tick}), t2 = P({x:pt.x+nx*tick, y:pt.y+ny*tick});
      return `<line x1="${t1.x}" y1="${t1.y}" x2="${t2.x}" y2="${t2.y}" stroke="#5a636d" stroke-width="1.5"/>`;
    };
    s += endTick(a) + endTick(b);
    const label = P({ x: midX + nx*(off+0.45), y: midY + ny*(off+0.45) });
    s += `<text x="${label.x}" y="${label.y}" font-size="24" font-weight="700" font-family="'IBM Plex Mono',monospace" fill="#1C2530" text-anchor="middle" dominant-baseline="middle" paint-order="stroke" stroke="#fff" stroke-width="5">${dimText}</text>`;
    return s;
  }
  function fpInteriorDimension(wall, X, Y, dimTxt){
    const midX = (wall.start.x+wall.end.x)/2, midY = (wall.start.y+wall.end.y)/2;
    const dx = wall.end.x-wall.start.x, dy = wall.end.y-wall.start.y;
    // Screen-space angle: SVG y grows down, so screen dy is (Y-projected)
    // but X/Y are linear scalings, angle from feet-space works with -dy.
    let angle = Math.atan2(dy, dx) * 180 / Math.PI;
    if(angle > 90) angle -= 180;
    if(angle < -90) angle += 180;
    const px = X(midX), py = Y(midY);
    return `<text x="${px}" y="${py}" transform="rotate(${angle} ${px} ${py})" dy="-7" font-size="18" font-weight="700" font-family="'IBM Plex Mono',monospace" fill="#2c3540" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="4">${dimTxt}</text>`;
  }
  function fpRoomSpanAt(poly, pt){
    if(!poly || poly.length < 3) return null;
    const xs = [], ys = [];
    for(let i=0, j=poly.length-1; i<poly.length; j=i++){
      const a = poly[j], b = poly[i];
      if((a.y <= pt.y) !== (b.y <= pt.y)){
        xs.push(a.x + (pt.y - a.y) / (b.y - a.y) * (b.x - a.x));
      }
      if((a.x <= pt.x) !== (b.x <= pt.x)){
        ys.push(a.y + (pt.x - a.x) / (b.x - a.x) * (b.y - a.y));
      }
    }
    xs.sort((p,q) => p-q); ys.sort((p,q) => p-q);
    let h = null, v = null;
    for(let i=0; i+1<xs.length; i++) if(xs[i] <= pt.x && pt.x <= xs[i+1]){ h = [xs[i], xs[i+1]]; break; }
    for(let i=0; i+1<ys.length; i++) if(ys[i] <= pt.y && pt.y <= ys[i+1]){ v = [ys[i], ys[i+1]]; break; }
    return { h, v };
  }
  function fpWallPolygonScreen(wall, X, Y){
    const dx = wall.end.x - wall.start.x, dy = wall.end.y - wall.start.y;
    const p = fpPerp(dx, dy);
    const h = FLOORPLAN_WALL_THICKNESS_FT/2;
    const corners = [
      { x: wall.start.x + p.x*h, y: wall.start.y + p.y*h },
      { x: wall.end.x   + p.x*h, y: wall.end.y   + p.y*h },
      { x: wall.end.x   - p.x*h, y: wall.end.y   - p.y*h },
      { x: wall.start.x - p.x*h, y: wall.start.y - p.y*h }
    ];
    return fpPts(corners.map(c => ({ x: X(c.x), y: Y(c.y) })));
  }
  function fpWallSolidSegments(wall, wallId, openings, foreignOpenings){
    const dx = wall.end.x - wall.start.x, dy = wall.end.y - wall.start.y;
    const L = Math.sqrt(dx*dx+dy*dy) || 1;
    const ux = dx/L, uy = dy/L;
    const gaps = [];
    (openings||[]).forEach(o => {
      if(String(o.wallId) !== String(wallId)) return;
      const w = floorplanOpeningEffectiveWidth(o) || 3;
      const t = (o.position.x-wall.start.x)*ux + (o.position.y-wall.start.y)*uy;
      const a = Math.max(0, t - w/2), b = Math.min(L, t + w/2);
      if(b > a) gaps.push([a,b]);
    });
    // Cross-room "help each other" pass (merged view only): a door or
    // passage detected by a NEIGHBORING room on this same physical wall
    // also cuts a gap here - real scans routinely have a doorway that
    // only one of the two adjoining rooms detected (the actual house
    // data had a Laundry->Kitchen door in the Laundry's list only, so
    // the Kitchen's copy of that shared wall drew solid across the
    // doorway). Matched geometrically: the foreign opening's position
    // must sit within 0.6ft of this wall's line and inside its span.
    (foreignOpenings||[]).forEach(o => {
      if(!o.position) return;
      const px = o.position.x-wall.start.x, py = o.position.y-wall.start.y;
      const t = px*ux + py*uy;
      if(t < -0.3 || t > L+0.3) return;
      const perp = Math.abs(px*(-uy) + py*ux);
      if(perp > 0.6) return;
      const w = floorplanOpeningEffectiveWidth(o) || 3;
      const a = Math.max(0, t - w/2), b = Math.min(L, t + w/2);
      if(b > a) gaps.push([a,b]);
    });
    gaps.sort((p,q) => p[0]-q[0]);
    const merged = [];
    gaps.forEach(g => {
      if(merged.length && g[0] <= merged[merged.length-1][1]){
        merged[merged.length-1][1] = Math.max(merged[merged.length-1][1], g[1]);
      } else merged.push(g.slice());
    });
    const segs = [];
    let cursor = 0;
    merged.forEach(([a,b]) => {
      if(a > cursor) segs.push([cursor, a]);
      cursor = Math.max(cursor, b);
    });
    if(cursor < L) segs.push([cursor, L]);
    const at = t => ({ x: wall.start.x + ux*t, y: wall.start.y + uy*t });
    return segs.map(([a,b]) => ({ start: at(a), end: at(b) }));
  }
  function fpDoorSwingMarkup(door, wall, centroid, X, Y){
    if(!wall) return '';
    const dx = wall.end.x - wall.start.x, dy = wall.end.y - wall.start.y;
    const len = Math.sqrt(dx*dx+dy*dy) || 1;
    let ux = dx/len, uy = dy/len;
    let nx = -uy, ny = ux;
    const toCx = centroid.x - door.position.x, toCy = centroid.y - door.position.y;
    if(nx*toCx + ny*toCy < 0){ nx = -nx; ny = -ny; }
    // Editor controls: _swingAcross opens the door into the OTHER room
    // (mirror across the wall); _hingeFlip moves the hinge to the other
    // jamb (mirror along the wall).
    if(door._swingAcross){ nx = -nx; ny = -ny; }
    if(door._hingeFlip){ ux = -ux; uy = -uy; }
    const w = floorplanOpeningEffectiveWidth(door) || 3;
    const style = door._doorStyle || 'single';
    const jambA = { x: door.position.x - ux*(w/2), y: door.position.y - uy*(w/2) };
    const jambB = { x: door.position.x + ux*(w/2), y: door.position.y + uy*(w/2) };
    const A = {x:X(jambA.x), y:Y(jambA.y)}, B = {x:X(jambB.x), y:Y(jambB.y)};
    const ftPx = Math.abs(X(1)-X(0)) || 1;
    if(style === 'sliding'){
      // Two offset parallel leaves - the standard sliding/bypass symbol.
      const off = 0.16*ftPx;
      const M = { x: (A.x+B.x)/2, y: (A.y+B.y)/2 };
      return `<line x1="${A.x + nx*off}" y1="${A.y + ny*off}" x2="${M.x + nx*off}" y2="${M.y + ny*off}" stroke="#1C2530" stroke-width="2.2"/>`
        + `<line x1="${M.x - nx*off}" y1="${M.y - ny*off}" x2="${B.x - nx*off}" y2="${B.y - ny*off}" stroke="#1C2530" stroke-width="2.2"/>`;
    }
    if(style === 'bifold'){
      // Two zigzag half-leaves folding toward the hinge jamb.
      const q1 = { x: A.x + (B.x-A.x)*0.25 + nx*0.55*ftPx, y: A.y + (B.y-A.y)*0.25 + ny*0.55*ftPx };
      const q3 = { x: A.x + (B.x-A.x)*0.75 + nx*0.55*ftPx, y: A.y + (B.y-A.y)*0.75 + ny*0.55*ftPx };
      const mid = { x: (A.x+B.x)/2, y: (A.y+B.y)/2 };
      return `<path d="M ${A.x} ${A.y} L ${q1.x} ${q1.y} L ${mid.x} ${mid.y} L ${q3.x} ${q3.y} L ${B.x} ${B.y}" fill="none" stroke="#1C2530" stroke-width="1.6"/>`;
    }
    if(style === 'double'){
      // Two leaves, two quarter arcs meeting in the middle.
      const mid = { x: (jambA.x+jambB.x)/2, y: (jambA.y+jambB.y)/2 };
      const oA = { x: jambA.x + nx*(w/2), y: jambA.y + ny*(w/2) };
      const oB = { x: jambB.x + nx*(w/2), y: jambB.y + ny*(w/2) };
      const M = {x:X(mid.x), y:Y(mid.y)}, OA = {x:X(oA.x), y:Y(oA.y)}, OB = {x:X(oB.x), y:Y(oB.y)};
      const r2 = Math.hypot(OA.x-A.x, OA.y-A.y);
      if(!(r2 > 0.5)) return '';
      return `<line x1="${A.x}" y1="${A.y}" x2="${OA.x}" y2="${OA.y}" stroke="#1C2530" stroke-width="1.6"/>`
        + `<path d="M ${M.x} ${M.y} A ${r2} ${r2} 0 0 1 ${OA.x} ${OA.y}" fill="none" stroke="#1C2530" stroke-width="1"/>`
        + `<line x1="${B.x}" y1="${B.y}" x2="${OB.x}" y2="${OB.y}" stroke="#1C2530" stroke-width="1.6"/>`
        + `<path d="M ${M.x} ${M.y} A ${r2} ${r2} 0 0 0 ${OB.x} ${OB.y}" fill="none" stroke="#1C2530" stroke-width="1"/>`;
    }
    const hinge = jambA, frame = jambB;
    const open = { x: hinge.x + nx*w, y: hinge.y + ny*w };
    const H = {x:X(hinge.x), y:Y(hinge.y)}, O = {x:X(open.x), y:Y(open.y)}, F = {x:X(frame.x), y:Y(frame.y)};
    const r = Math.hypot(O.x-H.x, O.y-H.y);
    if(!(r > 0.5)) return '';
    const sweep = ((ux * ny - uy * nx) > 0) ? 1 : 0;
    return `<line x1="${H.x}" y1="${H.y}" x2="${O.x}" y2="${O.y}" stroke="#1C2530" stroke-width="1.6"/>`
      + `<path d="M ${F.x} ${F.y} A ${r} ${r} 0 0 ${sweep} ${O.x} ${O.y}" fill="none" stroke="#1C2530" stroke-width="1"/>`;
  }
  function fpOpeningLabelPos(wall, centroid, pos, X, Y){
    if(!wall) return { x: X(pos.x), y: Y(pos.y) + 26 };
    const n = fpWallOutwardNormal(wall, centroid, pos);
    const off = 1.1;
    return { x: X(pos.x - n.x*off), y: Y(pos.y - n.y*off) };
  }
  function fpWindowMarkup(win, wall, X, Y){
    const cx = X(win.position.x), cy = Y(win.position.y);
    let ux = 1, uy = 0;
    if(wall){
      const dx = wall.end.x - wall.start.x, dy = wall.end.y - wall.start.y;
      const len = Math.sqrt(dx*dx+dy*dy) || 1;
      ux = dx/len; uy = dy/len;
    }
    const halfPx = ((floorplanOpeningEffectiveWidth(win)||3)/2) * ((X(1)-X(0)) || 1);
    const dxPx = ux*halfPx, dyPx = uy*halfPx;
    const p = fpPerp(dxPx, dyPx);
    const t = (FLOORPLAN_WALL_THICKNESS_FT/2) * ((X(1)-X(0)) || 1);
    // Classic architectural window: a white bar filling the wall cut,
    // outlined, with a center mullion line - monochrome, matching the
    // solid-black-wall professional style.
    const c1 = `${cx-dxPx+p.x*t},${cy-dyPx+p.y*t}`, c2 = `${cx+dxPx+p.x*t},${cy+dyPx+p.y*t}`;
    const c3 = `${cx+dxPx-p.x*t},${cy+dyPx-p.y*t}`, c4 = `${cx-dxPx-p.x*t},${cy-dyPx-p.y*t}`;
    // Heavier outline + mullion so the window bar reads as a solid part
    // of the wall run, not a thin break in it (field feedback: window
    // sections looked like the wall got thinner there).
    return `<polygon points="${c1} ${c2} ${c3} ${c4}" fill="#ffffff" stroke="#1C2530" stroke-width="2.2"/>`
      + `<line x1="${cx-dxPx}" y1="${cy-dyPx}" x2="${cx+dxPx}" y2="${cy+dyPx}" stroke="#1C2530" stroke-width="1.6"/>`;
  }
  function fpObjectIcon(category, ow, od){
    const hw = ow/2, hd = od/2, m = Math.min(hw,hd);
    switch(category){
      case 'sofa':
        return `<rect x="${-hw}" y="${-hd}" width="${ow}" height="${od*0.34}" fill="#ffffff" stroke="#1C2530" stroke-width="1"/>`
          + `<line x1="${-hw*0.55}" y1="${-hd}" x2="${-hw*0.55}" y2="${hd}" stroke="#1C2530" stroke-width="1"/>`
          + `<line x1="${hw*0.55}" y1="${-hd}" x2="${hw*0.55}" y2="${hd}" stroke="#1C2530" stroke-width="1"/>`;
      case 'bed':
        return `<rect x="${-hw}" y="${-hd}" width="${ow}" height="${od*0.24}" fill="#ffffff" stroke="#1C2530" stroke-width="1"/>`;
      case 'table':
        return `<rect x="${-hw*0.8}" y="${-hd*0.8}" width="${ow*0.8}" height="${od*0.8}" fill="none" stroke="#1C2530" stroke-width="1"/>`;
      case 'chair':
        return `<rect x="${-hw*0.7}" y="${-hd*0.7}" width="${ow*0.7}" height="${od*0.7}" rx="2" fill="#ffffff" stroke="#1C2530" stroke-width="1"/>`;
      case 'toilet':
        return `<rect x="${-hw*0.55}" y="${-hd}" width="${ow*0.55}" height="${od*0.32}" fill="#ffffff" stroke="#1C2530" stroke-width="1"/>`
          + `<ellipse cx="0" cy="${hd*0.22}" rx="${hw*0.55}" ry="${hd*0.5}" fill="none" stroke="#1C2530" stroke-width="1"/>`;
      case 'bathtub':
        return `<rect x="${-hw}" y="${-hd}" width="${ow}" height="${od}" rx="${m*0.35}" fill="#ffffff" stroke="#1C2530" stroke-width="1"/>`;
      case 'sink':
        return `<circle cx="0" cy="0" r="${m*0.55}" fill="none" stroke="#1C2530" stroke-width="1"/>`;
      case 'stove':
        return [[-hw*0.45,-hd*0.45],[hw*0.45,-hd*0.45],[-hw*0.45,hd*0.45],[hw*0.45,hd*0.45]]
          .map(p => `<circle cx="${p[0]}" cy="${p[1]}" r="${m*0.2}" fill="none" stroke="#1C2530" stroke-width="1"/>`).join('');
      case 'oven':
      case 'dishwasher':
        return `<rect x="${-hw*0.62}" y="${-hd*0.62}" width="${ow*0.62}" height="${od*0.62}" fill="none" stroke="#1C2530" stroke-width="1"/>`;
      case 'refrigerator':
        return `<line x1="0" y1="${-hd}" x2="0" y2="${hd}" stroke="#1C2530" stroke-width="1"/>`;
      case 'washerDryer':
        return `<circle cx="0" cy="0" r="${m*0.5}" fill="none" stroke="#1C2530" stroke-width="1"/>`;
      case 'storage':
        return `<line x1="0" y1="${-hd}" x2="0" y2="${hd}" stroke="#1C2530" stroke-width="1"/>`;
      case 'television':
        return `<rect x="${-hw}" y="${-hd*0.4}" width="${ow}" height="${od*0.8}" fill="#1C2530"/>`;
      case 'fireplace':
        return `<rect x="${-hw*0.6}" y="${-hd*0.6}" width="${ow*0.6}" height="${od*0.6}" fill="#ffffff" stroke="#1C2530" stroke-width="1"/>`;
      case 'stairs': {
        let s = '';
        for(let i=1;i<4;i++){ const yy = -hd + (od*i/4); s += `<line x1="${-hw}" y1="${yy}" x2="${hw}" y2="${yy}" stroke="#1C2530" stroke-width="0.75"/>`; }
        return s;
      }
      default: return '';
    }
  }
  function fpGuessedBoundaryFt(room){
    const gi = {};
    fpOrderedRoomPolygon(room, gi);
    return (gi.bridgeSegs || []).reduce((t, b) => t + (b && b.d > 1 ? b.d : 0), 0);
  }
  function fpPlanHasGuessedBoundary(data, onLevel){
    let rooms = 0, ft = 0;
    ((data && data.rooms) || []).forEach(r => {
      if(r.deleted || !(r.walls||[]).length) return;
      if(onLevel && !onLevel(r)) return;
      const g = fpGuessedBoundaryFt(r);
      if(g > 1){ rooms++; ft += g; }
    });
    return { rooms, ft };
  }
  function fpMirroredPortCheck(data, level){
    const rooms = ((data && data.rooms) || []).filter(r => !r.deleted);
    const ports = [];
    rooms.forEach((r, ri) => {
      if(level != null && (r.level||1) !== level) return;
      ['doors','openings'].forEach(kind => (r[kind]||[]).forEach((o, oi) => {
        if(!o || !o.position || o._removed) return;
        ports.push({ ri, roomName: r.roomName || `Room ${ri+1}`, kind, oi,
                     id: o.id, w: +o.widthFt || 0, p: o.position, lvl: r.level||1 });
      }));
    });
    // El MISMO objeto visto desde los dos lados. 1.0 ft es lo mas
    // estrecho que sigue emparejando los 3 pares reales de su casa.
    const paired = new Set();
    for(let i=0; i<ports.length; i++) for(let j=i+1; j<ports.length; j++){
      if(ports[i].ri === ports[j].ri || ports[i].lvl !== ports[j].lvl) continue;
      if(Math.hypot(ports[i].p.x-ports[j].p.x, ports[i].p.y-ports[j].p.y) <= 1.0){
        paired.add(i); paired.add(j);
      }
    }
    const out = [];
    ports.forEach((pt, i) => {
      if(paired.has(i)) return;
      // Un "paso" de media pulgada es ruido de RoomPlan, no una puerta.
      // Sin esta reja, el escaneo anterior daba 2 falsos positivos, los
      // dos de un opening de 0.04 ft. Con ella: 1 acierto, 0 falsos, en
      // los dos escaneos guardados.
      if(pt.w < 1.5) return;
      let best = null;
      rooms.forEach((r2, rj) => {
        if(rj === pt.ri || (r2.level||1) !== pt.lvl) return;
        (r2.walls||[]).forEach(w => {
          if(!w.start || !w.end) return;
          const dx = w.end.x-w.start.x, dy = w.end.y-w.start.y, L2 = dx*dx+dy*dy;
          if(L2 < 1e-6) return;
          const t = ((pt.p.x-w.start.x)*dx + (pt.p.y-w.start.y)*dy)/L2;
          // Dentro del segmento, no en la punta: una punta es una esquina,
          // y toda esquina tiene paredes de otros cuartos cerca.
          if(t < 0.05 || t > 0.95) return;
          const d = Math.hypot(pt.p.x-(w.start.x+dx*t), pt.p.y-(w.start.y+dy*t));
          if(d > 0.5) return;
          if(!best || d < best.d) best = { d, rj, roomName: r2.roomName || `Room ${rj+1}`, wallId: w.id };
        });
      });
      if(best) out.push({ fromRoom: pt.roomName, fromIdx: pt.ri, kind: pt.kind, oi: pt.oi,
                          widthFt: pt.w, x: pt.p.x, y: pt.p.y,
                          missingIn: best.roomName, missingIdx: best.rj,
                          wallId: best.wallId, distFt: Math.round(best.d*10000)/10000 });
    });
    return out;
  }
  function fpInferCorner(room, seg){
    if(!room || !seg || !seg.a || !seg.b) return null;
    const D = (p, q) => Math.hypot(p.x-q.x, p.y-q.y);
    let wa = null, wb = null;
    (room.walls||[]).forEach(w => {
      if(!w.start || !w.end) return;
      if(D(w.end, seg.a) < 0.35)   wa = { from: w.start, to: w.end };
      if(D(w.start, seg.a) < 0.35) wa = { from: w.end,   to: w.start };
      if(D(w.start, seg.b) < 0.35) wb = { from: w.end,   to: w.start };
      if(D(w.end, seg.b) < 0.35)   wb = { from: w.start, to: w.end };
    });
    if(!wa || !wb) return null;
    const u = (a, b) => { const dx=b.x-a.x, dy=b.y-a.y, L=Math.hypot(dx,dy);
      return L < 0.5 ? null : { x:dx/L, y:dy/L }; };
    const u1 = u(wa.from, wa.to), u2 = u(wb.from, wb.to);
    if(!u1 || !u2) return null;
    const meet = (p1, d1, p2, d2) => {
      const den = d1.x*d2.y - d1.y*d2.x;
      if(Math.abs(den) < 1e-6) return null;
      const t = ((p2.x-p1.x)*d2.y - (p2.y-p1.y)*d2.x) / den;
      const c = { x: p1.x + d1.x*t, y: p1.y + d1.y*t };
      return (isFinite(c.x) && isFinite(c.y)) ? c : null;
    };
    // El codo no puede caer encima de una pared que ya existe: eso seria
    // que el contorno se devuelve sobre si mismo, no una esquina.
    const onAWall = c => (room.walls||[]).some(w => {
      if(!w.start || !w.end) return false;
      const dx=w.end.x-w.start.x, dy=w.end.y-w.start.y, L2=dx*dx+dy*dy||1;
      let t = ((c.x-w.start.x)*dx + (c.y-w.start.y)*dy)/L2;
      t = Math.max(0, Math.min(1, t));
      return Math.hypot(c.x-(w.start.x+dx*t), c.y-(w.start.y+dy*t)) < 0.4;
    });
    const cap = Math.max(14, seg.d * 2.2);
    const ok = c => {
      if(!c || onAWall(c)) return null;
      const legA = D(seg.a, c), legB = D(seg.b, c);
      if(legA > cap || legB > cap) return null;
      if(legA < 0.2 && legB < 0.2) return null;
      return { x: Math.round(c.x*100)/100, y: Math.round(c.y*100)/100,
               legA: Math.round(legA*100)/100, legB: Math.round(legB*100)/100 };
    };

    // FORMA 1 - las dos paredes son los dos lados de UNA esquina, y solo
    // les falto el pedacito hasta el vertice. Solo vale si el vertice
    // queda HACIA ADELANTE de las dos: un cruce "hacia atras" obligaria al
    // contorno a devolverse encima de una pared existente. En la casa real
    // de Amilcar las tres roturas fallan justo aqui - parecian esquinas de
    // 90 grados pero exigian retroceder, asi que no lo son.
    const cornerAngle = Math.abs(Math.atan2(u1.x*u2.y - u1.y*u2.x, u1.x*u2.x + u1.y*u2.y) * 180/Math.PI);
    if(cornerAngle >= 55 && cornerAngle <= 125){
      const c1 = meet(wa.to, u1, wb.to, u2);
      if(c1){
        const fwdA = (c1.x-wa.to.x)*u1.x + (c1.y-wa.to.y)*u1.y;
        const fwdB = (c1.x-wb.to.x)*u2.x + (c1.y-wb.to.y)*u2.y;
        if(fwdA > -0.5 && fwdB > -0.5){
          const r1 = ok(c1);
          if(r1) return Object.assign(r1, { angle: Math.round(cornerAngle), kind: 'vertice' });
        }
      }
    }
    // FORMA 2 - "escuadrar el hueco": doblar 90 grados en cada punta y
    // encontrarse. Es la que corresponde cuando falta un PEDAZO del
    // contorno, no solo el vertice, y es la que aplica en su casa: los
    // tres codos caen en lugar limpio (Living Room 2'-11" + 10'-6",
    // Hallway 8'-10" + 6'-4", Bathroom 8'-8" + 0'-5").
    const n1 = { x:-u1.y, y:u1.x }, n2 = { x:-u2.y, y:u2.x };
    const c2 = meet(seg.a, n1, seg.b, n2);
    const r2 = ok(c2);
    if(r2) return Object.assign(r2, { angle: 90, kind: 'escuadra' });
    return null;
  }
  const FP_ESQ = {
    dMin: 1.0, dMax: 6.0,         // regla C: puentes del encadenado entre 1 y 6 ft (>6 sigue siendo "gap")
    autoD: 1.5, autoLeg: 1.2,     // solo se cierra solo si el puente ≤ 1.5 ft y cada prolongación ≤ 1.2 ft
    legMin: 0.75, wallMin: 1.0,   // pierna mínima (una puerta pegada a la esquina real da 0.03) y pared mínima
    thetaMin: 60, thetaMax: 120,  // una esquina; paralelas o casi colineales son una puerta o un desfase
    skewMin: 3, skewMax: 15, skewLen: 20, skewAuto: 0.35, skewMaxLat: 1.5,
    overMax: 1.0, overAuto: 0.35,
    reglaBTope: 0.75              // la regla B del enderezado ya no mueve una esquina más de esto sin preguntar
  };
  function fpLineMeet(a, u1, b, u2){
    const den = u1.x * u2.y - u1.y * u2.x;
    if(Math.abs(den) < 1e-6) return null;
    const t = ((b.x - a.x) * u2.y - (b.y - a.y) * u2.x) / den;
    const c = { x: a.x + u1.x * t, y: a.y + u1.y * t };
    if(!isFinite(c.x) || !isFinite(c.y)) return null;
    const s = (c.x - b.x) * u2.x + (c.y - b.y) * u2.y;
    return { c, t, s };
  }
  function fpSegmentoCubierto(data, seg, level, excluir){
    const vx = seg.b.x - seg.a.x, vy = seg.b.y - seg.a.y;
    const L = Math.hypot(vx, vy) || 1;
    const ux = vx / L, uy = vy / L, nx = -uy, ny = ux;
    const spans = [];
    ((data && data.rooms) || []).forEach(r => {
      if(r.deleted || (level != null && (r.level || 1) !== level)) return;
      (r.walls || []).forEach(w => {
        if(!w.start || !w.end || w._added || (excluir && excluir.indexOf(w) >= 0)) return;
        const dx = w.end.x - w.start.x, dy = w.end.y - w.start.y;
        const wl = Math.hypot(dx, dy) || 1;
        if(Math.abs((dx / wl) * ux + (dy / wl) * uy) < 0.95) return;
        const offA = (w.start.x - seg.a.x) * nx + (w.start.y - seg.a.y) * ny;
        const offB = (w.end.x - seg.a.x) * nx + (w.end.y - seg.a.y) * ny;
        if(Math.abs(offA) > 0.8 || Math.abs(offB) > 0.8) return;
        const t0 = (w.start.x - seg.a.x) * ux + (w.start.y - seg.a.y) * uy;
        const t1 = (w.end.x - seg.a.x) * ux + (w.end.y - seg.a.y) * uy;
        const lo = Math.max(0, Math.min(t0, t1)), hi = Math.min(L, Math.max(t0, t1));
        if(hi > lo) spans.push([lo, hi]);
      });
    });
    spans.sort((p, q) => p[0] - q[0]);
    let covered = 0, cursor = 0;
    spans.forEach(([lo, hi]) => { if(hi > cursor){ covered += hi - Math.max(lo, cursor); cursor = Math.max(cursor, hi); } });
    return covered >= L * 0.7;
  }
  function fpCornerFindings(data, ri){
    const room = ((data && data.rooms) || [])[ri];
    if(!room || room.deleted) return [];
    const walls = (room.walls || []).filter(w => w.start && w.end && !(w._studWall && !w._studPairId)
      && Math.hypot(w.end.x - w.start.x, w.end.y - w.start.y) > 0.05);
    if(walls.length < 3) return [];
    // Candado 1: un contorno frágil o que se devuelve sobre sí mismo no se
    // toca - ni solo ni a propuesta.
    if(fpAiFragileOutline(room) || fpOutlineDoublesBack(room)) return [];
    const level = room.level || 1;
    const merged = !(data && data.merged === false);
    const D = (p, q) => Math.hypot(p.x - q.x, p.y - q.y);
    const len = w => D(w.start, w.end);
    const r2 = v => Math.round(v * 100) / 100;
    const keyOf = p => (Math.round(p.x * 10) / 10).toFixed(1) + ',' + (Math.round(p.y * 10) / 10).toFixed(1);
    const puntas = [];
    walls.forEach(w => { puntas.push({ w, punta: 'start', p: w.start }); puntas.push({ w, punta: 'end', p: w.end }); });
    const grado = pt => puntas.filter(q => D(q.p, pt) <= 0.35).length;
    const puntaEn = p => puntas.find(q => D(q.p, p) <= 0.35 && grado(q.p) === 1) || null;
    // Vector unitario que va POR la pared hacia la punta dada.
    const hacia = (w, punta) => {
      const near = punta === 'end' ? w.end : w.start, far = punta === 'end' ? w.start : w.end;
      const L = D(far, near) || 1;
      return { x: (near.x - far.x) / L, y: (near.y - far.y) / L };
    };
    const anguloEntre = (u1, u2) => Math.acos(Math.max(-1, Math.min(1, Math.abs(u1.x * u2.x + u1.y * u2.y)))) * 180 / Math.PI;
    const aberturas = [].concat(room.doors || [], room.windows || [], room.openings || []).filter(o => o && o.position && !o._removed);
    const aberturaCerca = (p, ft) => aberturas.some(o => D(o.position, p) <= ft);
    const path = fpWalkedPath(data, level);
    const otrosCuartos = merged ? ((data.rooms || []).filter((r, i) => i !== ri && r && !r.deleted && (r.level || 1) === level)) : [];
    // Candado 7: el vértice nuevo no puede caer dentro del vecino ni encima
    // de una pared ajena (solo con el plano unido: sin unir, cada cuarto vive
    // en su propio marco y compararlos sería inventar).
    const vertexOk = c => {
      if(!merged) return true;
      for(const r of otrosCuartos){
        const poly = fpOrderedRoomPolygon(r);
        if(poly && poly.length >= 3 && fpPointInPolygon(c, poly) && fpDistToPolygon(c, poly) > 0.3) return false;
        for(const w of (r.walls || [])){
          if(!w.start || !w.end) continue;
          const dx = w.end.x - w.start.x, dy = w.end.y - w.start.y, L2 = dx * dx + dy * dy || 1;
          let t = ((c.x - w.start.x) * dx + (c.y - w.start.y) * dy) / L2; t = Math.max(0, Math.min(1, t));
          if(Math.hypot(c.x - (w.start.x + dx * t), c.y - (w.start.y + dy * t)) < 0.5) return false;
        }
      }
      return true;
    };
    const dobleTrazo = w => fpSegmentoCubierto(data, { a: w.start, b: w.end }, level, [w]);
    // Por PUNTA, no por pared entera (13 de septiembre): cerrar una
    // esquina de "fondo" no puede callar la OTRA esquina de "fondo" en el
    // otro extremo. Sin `punta` (regla D, que mueve el nodo entero) sigue
    // siendo un chequeo de la pared completa.
    const marcadas = (w, punta) => {
      const marcaEn = m => m && (punta === undefined || m.end === punta);
      if(marcaEn(w._cornerClosed) || marcaEn(w._cornerTrimmed)) return true;
      if(w._cornerSquared || w._cornerNodeMoved) return true;
      return false;
    };
    // Lo que el teléfono avisó al cerrar ese cuarto ("flagged on site"):
    // viaja en la inspección, por índice del cuarto entregado.
    const scan = ((data && data.inspection && data.inspection.scanCorners) || {})[String(ri)] || [];
    const delEscaneo = c => scan.some(s => s && isFinite(s.x) && isFinite(s.y) && D(s, c) <= 0.5);
    const out = [];

    // ---- REGLA C: el vértice que las dos paredes no alcanzaron ----
    const gi = {};
    fpOrderedRoomPolygon(room, gi);
    (gi.bridgeSegs || []).forEach(seg => {
      if(!(seg.d > FP_ESQ.dMin && seg.d <= FP_ESQ.dMax)) return;
      const A = puntaEn(seg.a), B = puntaEn(seg.b);           // candado 2: solo puntas sueltas
      if(!A || !B || A.w === B.w || marcadas(A.w, A.punta) || marcadas(B.w, B.punta)) return;
      const u1 = hacia(A.w, A.punta), u2 = hacia(B.w, B.punta);
      const theta = anguloEntre(u1, u2);
      if(theta < FP_ESQ.thetaMin || theta > FP_ESQ.thetaMax) return;   // candado 3
      if(len(A.w) < FP_ESQ.wallMin || len(B.w) < FP_ESQ.wallMin) return; // candado 4a
      const m = fpLineMeet(A.p, u1, B.p, u2);
      if(!m) return;
      const legA = m.t, legB = m.s;                             // hacia adelante = prolongar
      if(legA < FP_ESQ.legMin || legB < FP_ESQ.legMin) return;  // candado 4b (puerta pegada a esquina: 0.03)
      if(Math.max(legA, legB) > Math.min(6, 1.5 * seg.d)) return;
      if(dobleTrazo(A.w) || dobleTrazo(B.w)) return;            // candado 5
      if(fpSegmentoCubierto(data, seg, level, null)) return;    // candado 6: ya hay pared ahí
      if(fpAiOpeningOnBridge(data, seg, level)) return;         //   una puerta en el tramo
      if(aberturaCerca(seg.a, 1) || aberturaCerca(seg.b, 1)) return; // una abertura junto a la punta
      if(fpPathCrossesSegment(seg, path, 4)) return;            //   alguien caminó por ahí
      if(!vertexOk(m.c)) return;                                // candado 7
      const auto = seg.d <= FP_ESQ.autoD && Math.max(legA, legB) <= FP_ESQ.autoLeg;
      // El piso que gana el cuarto: el triángulo entre las dos puntas y el vértice.
      const floorDelta = Math.abs((seg.a.x - m.c.x) * (seg.b.y - m.c.y) - (seg.a.y - m.c.y) * (seg.b.x - m.c.x)) / 2;
      out.push({ kind: 'corner', band: auto ? 'auto' : 'propose', key: keyOf(m.c),
        wallA: A.w, puntaA: A.punta, wallB: B.w, puntaB: B.punta, vertex: { x: r2(m.c.x), y: r2(m.c.y) },
        seg, legA: r2(legA), legB: r2(legB), thetaDeg: Math.round(theta),
        perimDeltaFt: r2(legA + legB - seg.d), floorDeltaSqFt: r2(floorDelta),
        maxMoveFt: r2(Math.max(legA, legB)), fromScan: delEscaneo(m.c) });
    });

    // ---- REGLA D: la pared que llega torcida a la esquina ----
    const { nodes, ends } = fpBuildNodes(walls.map(w => ({ wall: w, roomIdx: ri })));
    const offAxisDeg = e => {
      const ang = Math.abs(Math.atan2(e.b.y - e.a.y, e.b.x - e.a.x)) * 180 / Math.PI % 180;
      return Math.min(ang % 90, 90 - (ang % 90));
    };
    const horiz = e => Math.abs(e.b.y - e.a.y) <= Math.abs(e.b.x - e.a.x);
    const lenE = e => Math.hypot(e.b.x - e.a.x, e.b.y - e.a.y);
    // Un cuarto "por lo demás recto": a lo sumo una pared torcida de cada
    // cinco (y en un cuarto de cuatro paredes, una).
    const rectas = ends.filter(e => offAxisDeg(e) <= 3).length;
    if(ends.length && (ends.length - rectas) <= Math.max(1, Math.floor(ends.length * 0.2))){
      ends.forEach(e => {
        const d = offAxisDeg(e);
        if(d <= FP_ESQ.skewMin || d > FP_ESQ.skewMax || lenE(e) > FP_ESQ.skewLen || marcadas(e.wall)) return;
        if(aberturas.some(o => String(o.wallId) === String(e.wall.id))) return;   // candado 8: no gira una pared con puertas
        // La pared torcida tiene dos esquinas y solo UNA está mal. Se mueve
        // la que comparte con el vecino MÁS CORTO (menos evidencia), igual
        // que la regla B del enderezado.
        const candidatos = [];
        [[e.a, e.b], [e.b, e.a]].forEach(([nodo, ancla]) => {
          if(nodo.refs.length !== 2 || ancla.refs.length !== 2) return;
          const vecino = ends.find(o => o !== e && (o.a === nodo || o.b === nodo));
          const otro = ends.find(o => o !== e && (o.a === ancla || o.b === ancla));
          if(!vecino || !otro || offAxisDeg(vecino) > 3 || offAxisDeg(otro) > 3 || lenE(vecino) < 2) return;
          if(horiz(vecino) === horiz(e)) return;   // colineal, no es una esquina
          // A dónde iría la esquina: la línea del ancla, por el eje de la pared.
          const destino = horiz(e) ? { x: nodo.x, y: ancla.y } : { x: ancla.x, y: nodo.y };
          const lateral = D(destino, nodo);
          if(lateral > FP_ESQ.skewMaxLat || lateral < 0.02) return;
          if(!vertexOk(destino)) return;
          candidatos.push({ nodo, destino, lateral, vecino });
        });
        if(!candidatos.length) return;
        candidatos.sort((p, q) => lenE(p.vecino) - lenE(q.vecino));
        const c = candidatos[0];
        const key = keyOf(c.nodo) + '>' + keyOf(c.destino);
        if(out.some(f => f.key === key)) return;
        out.push({ kind: 'skew', band: c.lateral <= FP_ESQ.skewAuto ? 'auto' : 'propose', key,
          wall: e.wall, nodo: c.nodo, destino: { x: r2(c.destino.x), y: r2(c.destino.y) },
          vecinoLen: r2(lenE(c.vecino)), skewDeg: Math.round(d), lateralFt: r2(c.lateral), maxMoveFt: r2(c.lateral) });
      });
    }

    // ---- REGLA E: dos paredes que se pasaron de la esquina (una X) ----
    for(let i = 0; i < walls.length; i++) for(let j = i + 1; j < walls.length; j++){
      const A = walls[i], B = walls[j];
      if(!fpSegmentsCross(A.start, A.end, B.start, B.end)) continue;
      const uA = hacia(A, 'end'), uB = hacia(B, 'end');
      const theta = anguloEntre(uA, uB);
      if(theta < FP_ESQ.thetaMin || theta > FP_ESQ.thetaMax) continue;
      const m = fpLineMeet(A.start, uA, B.start, uB);
      if(!m) continue;
      const LA = len(A), LB = len(B);
      const sobraA = Math.min(m.t, LA - m.t), sobraB = Math.min(m.s, LB - m.s);
      if(sobraA > FP_ESQ.overMax || sobraB > FP_ESQ.overMax || sobraA < 0.02 || sobraB < 0.02) continue;
      const puntaA = m.t < LA - m.t ? 'start' : 'end', puntaB = m.s < LB - m.s ? 'start' : 'end';
      // Por punta, no por pared: un recorte en el OTRO extremo de A o B no
      // calla esta pasada.
      if(marcadas(A, puntaA) || marcadas(B, puntaB)) continue;
      const tipA = A[puntaA], tipB = B[puntaB];
      if(grado(tipA) !== 1 || grado(tipB) !== 1) continue;          // punta solitaria
      // Una espina compartida con el vecino no se recorta: es su pared.
      if(fpSegmentoCubierto(data, { a: m.c, b: tipA }, level, [A]) || fpSegmentoCubierto(data, { a: m.c, b: tipB }, level, [B])) continue;
      if(aberturaCerca(tipA, 1) || aberturaCerca(tipB, 1)) continue;
      out.push({ kind: 'overshoot', band: (sobraA <= FP_ESQ.overAuto && sobraB <= FP_ESQ.overAuto) ? 'auto' : 'propose',
        key: 'x' + keyOf(m.c), wallA: A, puntaA, wallB: B, puntaB, vertex: { x: r2(m.c.x), y: r2(m.c.y) },
        sobraA: r2(sobraA), sobraB: r2(sobraB), maxMoveFt: r2(Math.max(sobraA, sobraB)) });
    }
    return out;
  }
  function fpWalkedPath(data, level){
    const raw = data && data.inspection && data.inspection.path;
    if(!Array.isArray(raw)) return [];
    return raw.filter(q => q && isFinite(q.x) && isFinite(q.y) &&
                           (level == null || (q.l || 1) === level));
  }
  function fpSegmentsCross(a1, a2, b1, b2){
    const d = (a2.x-a1.x)*(b2.y-b1.y) - (a2.y-a1.y)*(b2.x-b1.x);
    if(Math.abs(d) < 1e-9) return false;
    const t = ((b1.x-a1.x)*(b2.y-b1.y) - (b1.y-a1.y)*(b2.x-b1.x)) / d;
    const u = ((b1.x-a1.x)*(a2.y-a1.y) - (b1.y-a1.y)*(a2.x-a1.x)) / d;
    return t > 0.02 && t < 0.98 && u > 0.02 && u < 0.98;
  }
  function fpPathCrossesSegment(seg, path, maxStepFt){
    const step = maxStepFt || 4;
    for(let i = 1; i < path.length; i++){
      const p = path[i-1], q = path[i];
      if(Math.hypot(q.x-p.x, q.y-p.y) > step) continue;   // salto: no es un paso
      if(fpSegmentsCross(p, q, seg.a, seg.b)) return true;
    }
    return false;
  }
  function fpPathCrossesWalls(data, level){
    const path = fpWalkedPath(data, level);
    if(path.length < 2) return [];
    const hits = [];
    ((data && data.rooms) || []).forEach(r => {
      if(r.deleted) return;
      if(level != null && (r.level||1) !== level) return;
      const gaps = [];
      ['doors','windows','openings'].forEach(k => (r[k]||[]).forEach(o => {
        if(o && o.position && !o._removed) gaps.push(o);
      }));
      (r.walls||[]).forEach((w, wi) => {
        if(!w.start || !w.end) return;
        const L = Math.hypot(w.end.x-w.start.x, w.end.y-w.start.y);
        if(L < 2) return;
        // acorta la pared por las puntas: las esquinas siempre tienen ruido
        const ux = (w.end.x-w.start.x)/L, uy = (w.end.y-w.start.y)/L;
        const trim = Math.min(1.0, L*0.2);
        const seg = { a:{x:w.start.x+ux*trim, y:w.start.y+uy*trim},
                      b:{x:w.end.x-ux*trim,   y:w.end.y-uy*trim} };
        if(!fpPathCrossesSegment(seg, path, 3)) return;
        // ¿habia una puerta o un paso justo ahi? entonces no es contradiccion
        const near = gaps.some(o => {
          const dx = w.end.x-w.start.x, dy = w.end.y-w.start.y, L2 = dx*dx+dy*dy || 1;
          let t = ((o.position.x-w.start.x)*dx + (o.position.y-w.start.y)*dy)/L2;
          t = Math.max(0, Math.min(1, t));
          return Math.hypot(o.position.x-(w.start.x+dx*t), o.position.y-(w.start.y+dy*t)) <= 1.5;
        });
        if(!near) hits.push({ room: r.roomName || 'Room', wall: wi, lengthFt: L });
      });
    });
    return hits;
  }
  function fpRoomsOverlapSqFt(data, onLevel){
    const rooms = ((data && data.rooms) || []).filter(r =>
      !r.deleted && (r.walls||[]).length && (!onLevel || onLevel(r)));
    if(rooms.length < 2) return { pairs: [], sqFt: 0 };
    const polys = rooms.map(r => fpOrderedRoomPolygon(r));
    const boxes = polys.map(p => {
      if(!p || p.length < 3) return null;
      const xs = p.map(q => q.x), ys = p.map(q => q.y);
      return { x0:Math.min(...xs), x1:Math.max(...xs), y0:Math.min(...ys), y1:Math.max(...ys) };
    });
    const CELL = 0.5;
    const pairs = [];
    let total = 0;
    for(let i=0; i<rooms.length; i++) for(let j=i+1; j<rooms.length; j++){
      const A = polys[i], B = polys[j], ba = boxes[i], bb = boxes[j];
      if(!A || !B || !ba || !bb) continue;
      const x0 = Math.max(ba.x0, bb.x0), x1 = Math.min(ba.x1, bb.x1);
      const y0 = Math.max(ba.y0, bb.y0), y1 = Math.min(ba.y1, bb.y1);
      if(x1 - x0 < CELL || y1 - y0 < CELL) continue;      // ni se tocan
      let n = 0;
      for(let x = x0; x < x1; x += CELL) for(let y = y0; y < y1; y += CELL){
        const pt = { x: x + CELL/2, y: y + CELL/2 };
        if(fpPointInPolygon(pt, A) && fpPointInPolygon(pt, B)) n++;
      }
      const sq = n * CELL * CELL;
      // Un pelo de traslape es el grosor de una pared compartida, no un
      // error. 4 sq ft es mas o menos 2 ft de pared: por debajo de eso no
      // vale la pena molestarlo.
      if(sq >= 4){
        pairs.push({ a: rooms[i].roomName || `Room ${i+1}`, b: rooms[j].roomName || `Room ${j+1}`, sqFt: Math.round(sq*10)/10 });
        total += sq;
      }
    }
    return { pairs, sqFt: Math.round(total*10)/10 };
  }
  function fpWallsInsideOtherRooms(data, onLevel){
    const rooms = ((data && data.rooms) || []).filter(r =>
      !r.deleted && (r.walls||[]).length && (!onLevel || onLevel(r)));
    const polys = rooms.map(r => fpOrderedRoomPolygon(r));
    const edgeDist = (p, poly) => {
      let m = Infinity;
      for(let i=0;i<poly.length;i++){
        const a = poly[i], b = poly[(i+1)%poly.length];
        const dx = b.x-a.x, dy = b.y-a.y, L2 = dx*dx+dy*dy || 1e-9;
        let t = ((p.x-a.x)*dx + (p.y-a.y)*dy)/L2; t = Math.max(0, Math.min(1, t));
        m = Math.min(m, Math.hypot(p.x-(a.x+dx*t), p.y-(a.y+dy*t)));
      }
      return m;
    };
    const hits = [];
    rooms.forEach((r, ri) => (r.walls||[]).forEach((w, wi) => {
      if(!w.start || !w.end) return;
      if(Math.hypot(w.end.x-w.start.x, w.end.y-w.start.y) < 1) return;
      rooms.forEach((r2, ri2) => {
        if(ri2 === ri) return;
        const P = polys[ri2];
        if(!P || P.length < 3) return;
        let inside = 0, n = 0;
        for(let t = 0.15; t <= 0.85; t += 0.1){
          n++;
          const p = { x: w.start.x + (w.end.x-w.start.x)*t, y: w.start.y + (w.end.y-w.start.y)*t };
          if(fpPointInPolygon(p, P) && edgeDist(p, P) > 0.8) inside++;
        }
        if(n && inside/n > 0.8){
          hits.push({ room: r.roomName || `Room ${ri+1}`, wall: wi, inside: r2.roomName || `Room ${ri2+1}` });
        }
      });
    }));
    return hits;
  }
  function fpRoomFloorFill(room, X, Y){
    if(!room || (room.walls||[]).length < 3) return '';
    const gap = {};
    const poly = fpOrderedRoomPolygon(room, gap);
    if(!poly || poly.length < 3) return '';
    const pts = poly.map(p => ({ x: X(p.x), y: Y(p.y) }));
    // A repeated vertex means the outline doubles back on itself - the
    // shape is a traversal artifact, not a room boundary. Tint it, but
    // never let it read as a measured floor on an insurance document.
    // Tinting a doubled-back outline anyway does NOT remove the wedges:
    // under nonzero winding the crossed lobes stay bare, just in another
    // shade, and the traversal never encloses the missing floor in the
    // first place. An untinted room reads as "the app is not claiming
    // this floor", which is the truth, and floorplanValidate's "break in
    // the outline" item already carries the message with a one-tap fix.
    if(fpAiFragileOutline(room)) return '';
    let out = `<polygon points="${fpPts(pts)}" fill="${FLOORPLAN_FLOOR_FILL}"/>`;
    // Where the outline had to be BRIDGED, that run of the boundary is a
    // guess. Put the doubt on the segment that is actually doubtful
    // instead of over the whole room: measured on the real plan, only the
    // Master Bedroom is a true figure-eight (35% of its perimeter
    // bridged) - the others just bridge doorways, 0-22%, which is normal.
    (gap.bridgeSegs||[]).forEach(b => {
      if(!b || !b.a || !b.b || !(b.d > 4)) return;
      // If the two walls that reach this gap would meet at a real corner,
      // draw THAT instead of a straight diagonal. The diagonal is not the
      // shape of the room - on the real house it overstated the plan by 45
      // sq ft. Dashed either way: this side was never measured.
      const c = fpInferCorner(room, b);
      const dash = ` stroke="#b9c2cf" stroke-width="3" stroke-dasharray="14,10" fill="none"`;
      if(c){
        out += `<polyline points="${X(b.a.x)},${Y(b.a.y)} ${X(c.x)},${Y(c.y)} ${X(b.b.x)},${Y(b.b.y)}"${dash}/>`;
      } else {
        out += `<line x1="${X(b.a.x)}" y1="${Y(b.a.y)}" x2="${X(b.b.x)}" y2="${Y(b.b.y)}"${dash}/>`;
      }
    });
    return out;
  }
  function buildFloorplanRoomContent(room, roomIdx, X, Y, scale, allRooms, buildingCentroid, overlays, drawnObjectKeys, skipFloorFill){
    const centroid = floorplanRoomCentroid(room);
    const dimCentroid = buildingCentroid || centroid;
    const wallsById = {};
    (room.walls||[]).forEach((w, wi) => { wallsById[w.id != null ? w.id : wi] = w; });
    let s = '';
    const dims = [];

    // Floor tint. In the merged view every room's fill is painted FIRST,
    // in one pass, by the caller - rooms are emitted sequentially, so a
    // fill drawn here buried the previous room's walls, doors and
    // furniture (measured: 27 of 77 Hallway wall samples were overpainted).
    if(!skipFloorFill) s += fpRoomFloorFill(room, X, Y);

    // Walls as filled, properly-thick, hatched rectangles (the real
    // difference between a wireframe and an architectural drawing) -
    // corners naturally resolve where adjacent walls' rectangles overlap.
    // Each door/window on a wall cuts a real gap in it (fpWallSolidSegments)
    // rather than just drawing a symbol over an unbroken wall.
    // room.openings included: RoomPlan reports doorless passages (a cased
    // opening between two rooms) in their OWN list, separate from doors -
    // and this renderer previously ignored that list entirely, so a real
    // kitchen/living-room passage appeared as unbroken wall ("the kitchen
    // has a door but the floor plan didn't add it" - it was scanned as an
    // opening all along).
    const allOpenings = [].concat(room.doors||[], room.windows||[], room.openings||[]).filter(o => !o._removed);
    // Doors/passages every OTHER room detected - used so a doorway seen
    // from only one side still cuts through BOTH rooms' copies of the
    // shared wall (see fpWallSolidSegments). Windows excluded: they
    // never sit on interior shared walls.
    const foreignOpenings = [];
    if(allRooms){
      allRooms.forEach(other => {
        if(other === room) return;
        [].concat(other.doors||[], other.openings||[]).forEach(o => { if(!o._removed) foreignOpenings.push(o); });
      });
    }
    // RADIUS dedupe, not grid-cell equality: two detections of the same
    // physical thing 0.2ft apart could still straddle a 0.75ft grid line
    // and draw twice. Entries are stored as "kind@x,y" in the shared set
    // and a candidate is skipped when a same-kind entry lies within the
    // radius. Doors and doorless passages share one kind class ("doorway")
    // - the same physical doorway is often a door in one room's list and
    // an opening in the neighbor's.
    const seenNear = (kind, x, y) => {
      if(!drawnObjectKeys) return false;
      for(const entry of drawnObjectKeys){
        if(!entry.startsWith(kind + '@')) continue;
        const parts = entry.slice(kind.length + 1).split(',');
        if(Math.hypot(parseFloat(parts[0]) - x, parseFloat(parts[1]) - y) <= 0.75) return true;
      }
      drawnObjectKeys.add(`${kind}@${x.toFixed(2)},${y.toFixed(2)}`);
      return false;
    };
    (room.walls||[]).forEach((wall, wi) => {
      const rawWallId = wall.id != null ? wall.id : wi;
      const wallId = esc(String(rawWallId));
      const lowConf = wall.confidence === 'low';
      // La partición de solo studs se ve distinta a propósito: punteada en
      // ámbar. Es una pared que se COBRA (dos caras de drywall arrancado) y
      // no una que se mida en la casa.
      const stud = !!wall._studWall;
      const effLen = floorplanWallEffectiveLength(wall);
      const segments = fpWallSolidSegments(wall, rawWallId, allOpenings, foreignOpenings);
      // Solid near-black walls on white - professional architectural
      // convention. A low-confidence wall stays SOLID at the same full
      // thickness as every other wall (the earlier white-filled version
      // read as a thinner/broken section of the facade - field feedback:
      // "the thickness becomes different than the rest, make the same")
      // and is flagged by its red dashed outline + the validation panel
      // instead of by looking hollow.
      segments.forEach(seg => {
        const poly = fpWallPolygonScreen(seg, X, Y);
        s += `<polygon class="fp-wall" data-room-idx="${roomIdx}" data-wall-id="${wallId}" points="${poly}" fill="#1C2530" stroke="${stud ? '#8a6d1a' : lowConf ? '#c0392b' : '#1C2530'}" stroke-width="${(stud || lowConf) ? 2.2 : 0.75}"${stud ? ' stroke-dasharray="8,5"' : lowConf ? ' stroke-dasharray="6,4"' : ''} style="cursor:pointer;"/>`;
      });
      // If an opening spans the wall's whole length there's no solid
      // segment left to tap - a thin invisible line along the centerline
      // keeps the wall reachable for a length correction either way.
      if(!segments.length){
        s += `<line class="fp-wall" data-room-idx="${roomIdx}" data-wall-id="${wallId}" x1="${X(wall.start.x)}" y1="${Y(wall.start.y)}" x2="${X(wall.end.x)}" y2="${Y(wall.end.y)}" stroke="transparent" stroke-width="14" style="cursor:pointer;"/>`;
      }
      // Only the building's true exterior walls get a dimension line -
      // an interior wall shared between two rooms is skipped entirely
      // rather than drawn twice (once per neighboring room), which is
      // what used to crowd a shared wall/doorway. Exterior walls are
      // measured against the WHOLE building's centroid, not just this
      // room's own, so "outward" stays consistent and every exterior
      // dimension line sits at the same offset around one clean
      // perimeter band instead of drifting per-room.
      // EVERY measurable wall gets its dimension - exterior walls with
      // the full offset dimension line around the perimeter, interior
      // walls with a compact measurement set along the wall itself
      // (drawn once per physical wall via the shared-position key, since
      // both adjoining rooms carry their own copy). Stub segments under
      // 2ft are skipped as unmeasurable noise, and low-confidence walls
      // are separately flagged by the validation panel.
      // Una esquina que la app cerró SOLA lleva su propia marca (†), no la
      // de "a mano": la hoja tiene que decir quién movió qué.
      const autoMark = (!fpSheetExport && (wall._cornerClosed || wall._cornerTrimmed || wall._cornerSquared || wall._cornerNodeMoved)) ? '†' : '';
      const handMark = (!fpSheetExport && (wall._lengthOverrideFt != null || wall._squared || wall._movedByHand || wall._geomEdited || wall._added)) ? '*' : autoMark;
      const dimTxt = `${fpFeetInches(effLen)}${handMark}`;
      // ONE dimension per physical wall, whichever branch draws it. The
      // dedupe used to guard only the interior branch, so a wall that
      // floorplanIsExteriorWall called exterior in BOTH of the rooms that
      // share it printed the same measurement twice at the same point -
      // reproduced on the real plan: Living Room wall 6 and Hallway wall 2
      // are the same 2'-4" wall, 0.00 ft apart, and "2'-4"*" was stamped
      // on itself. Sharing one key across the two branches also stops a
      // wall called exterior in one room and interior in the other from
      // getting two differently-styled measurements.
      const midX = (wall.start.x+wall.end.x)/2, midY = (wall.start.y+wall.end.y)/2;
      // A genuinely zero-length wall exists in the real scan (Hallway
      // wall 4, start === end) and printed "0'-0"" on the plan.
      if(!FP_VISTA_LIMPIA && effLen >= 0.25 && !seenNear('dim', midX, midY)){
        if(floorplanIsExteriorWall(wall, room, allRooms)){
          dims.push(fpDimensionLine(wall, dimCentroid, X, Y, dimTxt));
        } else if(effLen >= 2 && fpMeasurePrefs.interior){
          dims.push(fpInteriorDimension(wall, X, Y, dimTxt));
        }
      }
    });

    // Doors and windows drawn on top of the wall so their symbols read
    // clearly against it. Each gets a tap target (an invisible circle,
    // same pattern as objects/walls) so its width/height can be corrected
    // the same way a wall's length can.
    // Door dimensions are deliberately NOT drawn on the plan itself
    // (decluttering, per your own instruction to prioritize room
    // dimensions/sq ft over secondary detail) - the door is still fully
    // tappable and its real width/height are still there, editable, in
    // its detail panel, just not floating text on the main drawing.
    // The same physical door/window/passage is often detected by BOTH
    // adjoining rooms at slightly different positions (real data: the
    // hallway/laundry door 0.23ft apart in the two lists) - in the
    // merged view each draws once, keyed by kind + a coarse position
    // grid (same mechanism as the object dedupe).
    (room.doors||[]).forEach((d, di) => {
      if(d._removed) return;
      if(seenNear('doorway', d.position.x, d.position.y)) return;
      s += fpDoorSwingMarkup(d, wallsById[d.wallId], centroid, X, Y);
      const cx = X(d.position.x), cy = Y(d.position.y);
      const dId = esc(String(d.id != null ? d.id : di));
      s += fpOpeningHitTarget('fp-door', roomIdx, dId, d, wallsById[d.wallId], X, Y);
      if(fpMeasurePrefs.openings && !FP_VISTA_LIMPIA){
        const dw = floorplanOpeningEffectiveWidth(d);
        if(dw >= 1){
          // dimCentroid, not centroid: fpDimensionLine offsets its text
          // AWAY from the building centre while this offsets INTO the
          // room. With two different reference points the two 'opposite
          // lanes' can resolve to the SAME side - measured on the real
          // plan, a 3'-0" door width landed 0.51 ft from a 4'-9" wall
          // dimension because one used the building centre and the other
          // the room centre.
          const dl = fpOpeningLabelPos(wallsById[d.wallId], dimCentroid, d.position, X, Y);
          s += `<text x="${dl.x}" y="${dl.y}" font-size="17" font-weight="700" fill="#7a6248" text-anchor="middle" dominant-baseline="middle" paint-order="stroke" stroke="#fff" stroke-width="5">${fpFeetInches(dw)}${(!fpSheetExport && d._added) ? '*' : ''}</text>`;
        }
      }
    });
    (room.windows||[]).forEach((win, wi2) => {
      if(win._removed) return;
      if(seenNear('window', win.position.x, win.position.y)) return;
      s += fpWindowMarkup(win, wallsById[win.wallId], X, Y);
      const cx = X(win.position.x), cy = Y(win.position.y);
      const winId = esc(String(win.id != null ? win.id : wi2));
      const ww = floorplanOpeningEffectiveWidth(win), wh = floorplanOpeningEffectiveHeight(win);
      s += fpOpeningHitTarget('fp-window', roomIdx, winId, win, wallsById[win.wallId], X, Y);
      if(fpMeasurePrefs.openings && !FP_VISTA_LIMPIA){
        const winLabel = fpOpeningLabelPos(wallsById[win.wallId], dimCentroid, win.position, X, Y);
        s += `<text x="${winLabel.x}" y="${winLabel.y}" font-size="19" font-weight="700" fill="#39699e" text-anchor="middle" dominant-baseline="middle" paint-order="stroke" stroke="#fff" stroke-width="5">${fpFeetInches(ww)} x ${fpFeetInches(wh)}${(!fpSheetExport && win._added) ? '*' : ''}</text>`;
      }
    });
    // A doorless passage: the wall gap is already cut (allOpenings above);
    // a thin dashed header line across the span marks it as an intentional
    // opening rather than a hole in the scan - the standard drafting
    // convention for a cased opening. The scanner's own classification
    // can be corrected from the validation panel (`_kindOverride`) - a
    // reclassified opening draws as a real door swing or window symbol
    // instead.
    (room.openings||[]).forEach((op) => {
      const wall = wallsById[op.wallId];
      if(!wall || !op.position || op._removed) return;
      const kindClass = op._kindOverride === 'window' ? 'window' : 'doorway';
      if(seenNear(kindClass, op.position.x, op.position.y)) return;
      if(op._kindOverride === 'door'){
        s += fpDoorSwingMarkup(op, wall, centroid, X, Y);
        return;
      }
      if(op._kindOverride === 'window'){
        s += fpWindowMarkup(op, wall, X, Y);
        return;
      }
      const wdx = wall.end.x-wall.start.x, wdy = wall.end.y-wall.start.y;
      const L = Math.hypot(wdx,wdy)||1, ux=wdx/L, uy=wdy/L;
      const w = floorplanOpeningEffectiveWidth(op) || 3;
      const a = { x: op.position.x - ux*w/2, y: op.position.y - uy*w/2 };
      const b = { x: op.position.x + ux*w/2, y: op.position.y + uy*w/2 };
      s += `<line x1="${X(a.x)}" y1="${Y(a.y)}" x2="${X(b.x)}" y2="${Y(b.y)}" stroke="#9aa3ad" stroke-width="2" stroke-dasharray="6,4"/>`;
    });

    (room.objects||[]).forEach((o, idx) => {
      if(o._hidden) return;
      // Movable furniture stays OFF the drawing unless the Measure menu
      // turns it on - fixtures always draw, and anything the tech added
      // or named by hand was a deliberate act, so it draws too.
      if(!fpMeasurePrefs.furniture && !o._added && !o._label && FP_MOVABLE_CATEGORIES.includes(o.category)) return;
      // Dedupe across rooms in the merged view: the same physical object
      // can appear in two adjacent rooms' lists - one drawing per real
      // object, radius-matched by category (see seenNear above).
      if(seenNear(`obj:${o.category}`, o.center.x, o.center.y)) return;
      const ow = (o.widthFt||1)*scale, od = (o.depthFt||1)*scale;
      const cx = X(o.center.x), cy = Y(o.center.y);
      const objId = esc(String(o.id != null ? o.id : idx));
      // Secondary/low-information categories (RoomPlan's own generic
      // "storage"/"unknown" buckets, when the tech hasn't typed a more
      // specific label over one) get no floating text label AND a
      // deliberately faint, dashed treatment - a real scan produced ten
      // unlabeled solid "storage" slabs (one 10ft long) that read as
      // unexplained gray shapes on the plan. Still fully tappable.
      const isSecondary = !o._label && (o.category === 'storage' || o.category === 'unknown');
      const stroke = o._confirmed ? '#3ddc84' : (isSecondary ? '#9aa3ad' : '#1C2530');
      const strokeW = o._confirmed ? 2 : 1;
      const fill = '#ffffff';
      const dash = '';
      // Reference-style plans carry no fixture text - the shape IS the
      // label. Text renders only when the tech typed a custom label
      // (a deliberate act worth showing); everything stays tappable.
      const label = esc(o._label || floorplanCategoryLabel(o.category));
      const showLabel = !!o._label;
      s += `<g class="fp-obj" data-room-idx="${roomIdx}" data-obj-id="${objId}" style="cursor:pointer;">`
        + `<g transform="translate(${cx},${cy}) rotate(${o.rotationDeg||0})">`
        + `<rect x="${-ow/2}" y="${-od/2}" width="${ow}" height="${od}" rx="2" fill="${fill}" stroke="${stroke}" stroke-width="${strokeW}"${dash}/>`
        + (isSecondary ? '' : fpObjectIcon(o.category, ow, od))
        + `</g>`
        + (showLabel ? `<text x="${cx}" y="${cy+od/2+20}" font-size="18" font-weight="600" fill="#3A4552" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="5">${label}</text>` : '')
        + `</g>`;
    });
    // Dimension lines paint LAST within this room's own markup (above
    // its furniture) - and in the merged view they're lifted out
    // entirely, above every room's content.
    if(overlays) overlays.push(dims.join(''));
    else s += dims.join('');
    return s;
  }
  function fpCompassAndScale(svgW, svgH, scale){
    const cx = svgW - 32, cy = 32;
    let s = `<g font-family="'IBM Plex Sans',sans-serif">`;
    s += `<circle cx="${cx}" cy="${cy}" r="18" fill="#fff" stroke="#c7cdd6" stroke-width="1"/>`;
    s += `<path d="M ${cx} ${cy-13} L ${cx-5} ${cy+7} L ${cx} ${cy+2} L ${cx+5} ${cy+7} Z" fill="#3A4552"/>`;
    s += `<text x="${cx}" y="${cy-20}" font-size="12" font-weight="700" fill="#8a95a3" text-anchor="middle">N</text>`;
    const barLenFt = scale >= 40 ? 5 : 10;
    const barPx = barLenFt * scale;
    const bx = 16, by = svgH - 16;
    s += `<line x1="${bx}" y1="${by}" x2="${bx+barPx}" y2="${by}" stroke="#3A4552" stroke-width="2"/>`;
    s += `<line x1="${bx}" y1="${by-4}" x2="${bx}" y2="${by+4}" stroke="#3A4552" stroke-width="2"/>`;
    s += `<line x1="${bx+barPx}" y1="${by-4}" x2="${bx+barPx}" y2="${by+4}" stroke="#3A4552" stroke-width="2"/>`;
    s += `<text x="${bx}" y="${by-10}" font-size="12" font-weight="600" fill="#3A4552">${barLenFt} ft</text>`;
    s += `</g>`;
    return s;
  }
  function fpJobInfo(){ return FP_JOB_SCANOVA; }
  let FP_JOB_SCANOVA = { client:'', address:'', date:'', claim:'', tech:'', phone:'' };
  export function ponerTrabajo(j){ FP_JOB_SCANOVA = Object.assign({ client:'', address:'', date:'', claim:'', tech:'', phone:'' }, j || {}); }
  const FLOORPLAN_STAMP_HEIGHT = 118;
  function fpTitleBlock(svgW, drawH, data){
    const y0 = drawH;
    const company = esc(($('#companyName') && $('#companyName').value) || 'Scanova360');
    const b = data.buildingSummary || {};
    const levels = floorplanLevels(data);
    const roomCount = b.roomCount || (data.rooms||[]).length;
    const job = (data && data.job) || fpJobInfo();
    const dateTxt = job.date
      ? new Date(job.date + 'T12:00:00').toLocaleDateString('en-US', {year:'numeric', month:'short', day:'numeric'})
      : new Date().toLocaleDateString('en-US', {year:'numeric', month:'short', day:'numeric'});
    let s = `<g font-family="'IBM Plex Sans',sans-serif">`;
    s += `<rect x="0" y="${y0}" width="${svgW}" height="${FLOORPLAN_STAMP_HEIGHT}" fill="#f7f8f9"/>`;
    s += `<line x1="0" y1="${y0}" x2="${svgW}" y2="${y0}" stroke="#1C2530" stroke-width="2"/>`;
    s += `<text x="18" y="${y0+28}" font-size="12" font-weight="700" font-family="'Oswald',sans-serif" letter-spacing="0.12em" fill="#D2601A" text-anchor="start">${company.toUpperCase()}</text>`;
    s += `<text x="18" y="${y0+60}" font-size="21" font-weight="700" font-family="'Oswald',sans-serif" letter-spacing="0.04em" fill="#1C2530" text-anchor="start">${fpRenderMode === 'moisture' ? 'MOISTURE MAP' : 'FLOOR PLAN'}</text>`;
    const who = [job.client, job.phone, job.address].filter(Boolean).join(' \u00b7 ');
    s += `<text x="18" y="${y0+82}" font-size="13" font-weight="700" fill="#1C2530" text-anchor="start">${esc(who || 'No client on this plan')}</text>`;
    const sub = [dateTxt, job.claim ? 'Claim ' + job.claim : '', job.tech].filter(Boolean).join(' \u00b7 ');
    s += `<text x="18" y="${y0+102}" font-size="11.5" font-weight="500" fill="#5a6472" text-anchor="start">${esc(sub)}</text>`;
    // Hand-edit stamp travels INSIDE the svg, so the viewer, the preview
    // thumbnail, and the PDF all carry it identically.
    {
      const sellos = [];
      if(data._handEdited){
        const manual = fpManualEditSummary(data);
        const n = manual ? manual.total : 0;
        sellos.push(`* = adjusted by hand${n ? ` (${n} edit${n>1?'s':''})` : ''}`);
      }
      // Lo que el asistente de esquinas cerró solo, dicho en la hoja: cuántas
      // y cuánto se movió como máximo. Es la app, no la mano.
      const c = data._corners;
      if(c && (c.closed || c.squared || c.trimmed)){
        const partes = [];
        if(c.closed) partes.push(`${c.closed} closed where the scanned walls meet`);
        if(c.squared) partes.push(`${c.squared} squared`);
        if(c.trimmed) partes.push(`${c.trimmed} trimmed`);
        sellos.push(`† corners: ${partes.join(', ')} (max ${fpFeetInches(c.maxMoveFt)})`);
      }
      if(sellos.length) s += `<text x="${svgW - 18}" y="${y0+102}" font-size="11" font-weight="600" fill="#b8860b" text-anchor="end">${esc(sellos.join(' · '))}</text>`;
    }
    const rx = svgW - 18;
    const multiLvl = floorplanLevels(data).length > 1;
    const guessed = fpPlanHasGuessedBoundary(data, r => !multiLvl || (r.level||1) === floorplanSelectedLevel);
    s += `<text x="${rx}" y="${y0+28}" font-size="11" font-weight="700" letter-spacing="0.08em" fill="#8a95a3" text-anchor="end">TOTAL AREA${guessed.rooms ? ' (APPROX.)' : ''}</text>`;
    s += `<text x="${rx}" y="${y0+60}" font-size="21" font-weight="700" font-family="'IBM Plex Mono',monospace" fill="#1C2530" text-anchor="end">${fpDisplayTotalAreaSqFt(data).toFixed(1)} sq ft</text>`;
    // Says WHICH part is estimated, on the sheet itself - the exported PDF
    // skips the on-screen legend, so this is the only place an adjuster
    // reading the paper would ever learn it.
    if(guessed.rooms){
      s += `<text x="${rx}" y="${y0+78}" font-size="11" font-weight="600" fill="#8a95a3" text-anchor="end">`
        + `${guessed.rooms} room${guessed.rooms>1?'s':''}: ${Math.round(guessed.ft)} ft of boundary closed by the app (shown dashed)</text>`;
    }
    const roomsTxt = `${roomCount} room${roomCount===1?'':'s'}${levels.length>1 ? ' · ' + levels.length + ' levels' : ''}`;
    s += `<text x="${rx}" y="${y0+84}" font-size="12" font-weight="500" fill="#5a6472" text-anchor="end">${esc(roomsTxt)}</text>`;
    s += `</g>`;
    return s;
  }
  function buildFloorplanSvgMerged(data, level){
    const onLevel = r => level == null || (r.level||1) === level;
    // Voice-deleted rooms (room.deleted, the native soft flag) are
    // excluded from the drawing, the bounding box, AND the neighbor set
    // used for exterior-wall detection - the native side already
    // excludes them from buildingSummary totals, so drawing them here
    // showed rooms the totals didn't count.
    const rooms = (data.rooms||[]).filter(r => (r.walls||[]).length && onLevel(r) && !r.deleted);
    if(!rooms.length) return '<p style="color:#888; padding:20px; text-align:center;">No data yet.</p>';
    let minX=Infinity, maxX=-Infinity, minY=Infinity, maxY=-Infinity;
    rooms.forEach(room => {
      const b = floorplanRoomBounds(room);
      minX=Math.min(minX,b.minX); maxX=Math.max(maxX,b.maxX);
      minY=Math.min(minY,b.minY); maxY=Math.max(maxY,b.maxY);
    });
    // 3ft of margin, not 1.5: exterior dimension lines sit 1ft outside
    // the walls with their measurement text centered ~1.45ft out - at
    // 1.5ft of margin that text sat basically ON the sheet border and
    // clipped, which on an insurance document reads as missing
    // measurements. 3ft leaves the full dimension string comfortably
    // inside the sheet on every side.
    const pad = FP_VISTA_LIMPIA ? 1.0 : 3.0;
    minX-=pad; minY-=pad; maxX+=pad; maxY+=pad;
    const w = Math.max(1, maxX-minX), h = Math.max(1, maxY-minY);
    const scale = FLOORPLAN_SVG_SCALE;
    const svgW = w*scale, svgH = h*scale;
    const totalSvgH = svgH + (fpSheetExport ? 0 : FLOORPLAN_STAMP_HEIGHT);
    const X = x => (x-minX)*scale;
    const Y = y => (y-minY)*scale;

    // Rendered at its real pixel size (no width:100%/max-width shrink-to-fit)
    // - SVG text scales down WITH the drawing when the whole thing gets
    // squeezed to fit a narrow phone screen, which is what was making every
    // measurement unreadable. #floorplanSvgWrap's overflow:auto (already
    // set) turns this into a pannable plan instead - the standard way any
    // blueprint viewer handles a plan wider than the screen, rather than
    // shrinking it until the numbers disappear.
    let s = `<svg viewBox="0 0 ${svgW} ${totalSvgH}" width="${svgW}" height="${totalSvgH}" data-fp-minx="${minX}" data-fp-miny="${minY}" data-fp-scale="${scale}" style="display:block; background:#fff;" xmlns="http://www.w3.org/2000/svg">`;
    s += fpDefs();
    if(!fpSheetExport) s += `<rect x="1" y="1" width="${svgW-2}" height="${totalSvgH-2}" fill="none" stroke="#dfe4ea" stroke-width="1"/>`;
    const buildingCentroid = floorplanBuildingCentroid(rooms);
    // Top layer, painted after EVERY room's content: dimension lines and
    // room labels can never be covered by another room's furniture.
    const overlays = [];
    const drawnObjectKeys = new Set();
    // Every room's floor tint goes down FIRST, in its own pass. Rooms are
    // emitted one after another, so a room that painted its own floor at
    // the top of its block buried the PREVIOUS room's walls, doors and
    // furniture (measured on the real plan: 27 of 77 Hallway wall samples
    // were overpainted by a later room's fill).
    (data.rooms||[]).forEach(room => {
      if(!(room.walls||[]).length || !onLevel(room) || room.deleted) return;
      s += fpRoomFloorFill(room, X, Y);
    });
    (data.rooms||[]).forEach((room, idx) => {
      if(!(room.walls||[]).length || !onLevel(room) || room.deleted) return;
      s += buildFloorplanRoomContent(room, idx, X, Y, scale, rooms, buildingCentroid, overlays, drawnObjectKeys, true);
      // A manually-positioned label anchors at the PLAIN geometric
      // center plus its own saved offset - the learned bias only steers
      // rooms with no manual override (applying it under an override
      // made pinned labels silently drift as new corrections changed
      // the bias). Un-overridden rooms get floorplanSmartLabelAnchor:
      // the guaranteed-inside geometric center, nudged by the pattern
      // of past manual corrections. Wrapped in one draggable <g> so the
      // whole name/area/dimensions stack moves together.
      const c = room._labelOffsetPx ? floorplanLabelAnchor(room) : floorplanSmartLabelAnchor(room);
      const labelOff = room._labelOffsetPx || {dx:0, dy:0};
      const labelX = X(c.x) + labelOff.dx, labelY = Y(c.y) + labelOff.dy;
      const label = esc((room.roomName || `Room ${idx+1}`).toUpperCase());
      // "approx." after the unit, not inside the number - a room whose
      // boundary the app had to close for itself must not print a bare
      // figure on a document someone bills from.
      const areaTxt = fpRoomDisplayAreaSqFt(room).toFixed(1) + ' sq ft'
        + (fpGuessedBoundaryFt(room) > 1 ? ' approx.' : '');
      // Overall room dimensions (width x depth), not just area - the
      // bounding box of its own walls, which is exactly the room's real
      // width/depth for a rectangular room now that the whole plan is
      // rotated to be axis-aligned (see floorplanAlignRooms above).
      const rb = floorplanRoomBounds(room);
      const dimTxt = `${fpFeetInches(rb.maxX-rb.minX)} x ${fpFeetInches(rb.maxY-rb.minY)}`;
      // Small areas (closets, water-heater nooks) keep their full
      // name/dimensions/sq-ft stack - scaled down to fit INSIDE the room
      // instead of spilling across neighbors. Floor: 55% keeps the text
      // printable on the insurance PDF.
      const areaNum = fpRoomDisplayAreaSqFt(room);
      const kAuto = areaNum > 0 && areaNum < 45 ? Math.max(0.55, Math.sqrt(areaNum/45)) : 1;
      // Per-room label scale (A-/A+ in the room panel) rides ON TOP of the
      // automatic small-room shrink, so "make it bigger" works everywhere.
      const k = FP_VISTA_LIMPIA ? fpKVista(label, dimTxt, rb, X, Y, labelX, labelY) : kAuto * (room._labelScale || 1);
      const f = v => (v*k).toFixed(1);
      // Room span markers (Measure toggle): ONLY small triangles, one
      // pointing at each wall the room runs to - no connecting lines
      // (field feedback: "just the small triangular... I don't need the
      // lines"). Each sits just INSIDE the room, clear of the black wall
      // body, so it reads plainly on the white floor. Viewer only; never
      // on the exported sheet, which stays a clean professional document.
      if(!fpSheetExport && fpMeasurePrefs.extents !== false && areaNum >= 20){
        const span = fpRoomSpanAt(fpOrderedRoomPolygon(room), c);
        // Span crossings land on wall CENTERLINES - pull each marker in
        // by half the wall thickness plus a gap so it floats visibly on
        // the floor instead of half-buried in the wall.
        const inset = FLOORPLAN_WALL_THICKNESS_FT/2 + 0.2;
        const tri = (x2, y2, dir) => {
          const s3 = 13;
          const pts = dir==='l' ? `${x2},${y2} ${x2+s3},${y2-s3*0.55} ${x2+s3},${y2+s3*0.55}`
            : dir==='r' ? `${x2},${y2} ${x2-s3},${y2-s3*0.55} ${x2-s3},${y2+s3*0.55}`
            : dir==='u' ? `${x2},${y2} ${x2-s3*0.55},${y2+s3} ${x2+s3*0.55},${y2+s3}`
            : `${x2},${y2} ${x2-s3*0.55},${y2-s3} ${x2+s3*0.55},${y2-s3}`;
          return `<polygon points="${pts}" fill="#7d8797" opacity="0.92"/>`;
        };
        let gArr = '';
        if(span && span.h && (span.h[1]-span.h[0]) > 3){
          const yPx = Y(c.y);
          gArr += tri(X(span.h[0] + inset), yPx, 'l') + tri(X(span.h[1] - inset), yPx, 'r');
        }
        if(span && span.v && (span.v[1]-span.v[0]) > 3){
          const xPx = X(c.x);
          gArr += tri(xPx, Y(span.v[0] + inset), 'u') + tri(xPx, Y(span.v[1] - inset), 'd');
        }
        if(gArr) overlays.push(`<g class="fp-extent" style="pointer-events:none;">${gArr}</g>`);
      }
      // Stack order per explicit instruction: room name, then the room's
      // DIMENSIONS, then the square footage under them. Pushed to the
      // overlay layer so no later room's furniture can paint over it.
      const labelLines = fpMeasurePrefs.roomArea
        ? `<text x="${labelX}" y="${labelY-(FP_VISTA_LIMPIA ? 32 : 48)*k}" font-size="${f(30)}" font-weight="700" letter-spacing="0.5" font-family="'IBM Plex Sans',sans-serif" fill="#1C2530" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="${f(6)}">${label}</text>`
          + `<text x="${labelX}" y="${labelY+(FP_VISTA_LIMPIA ? 2 : -14)*k}" font-size="${f(23)}" font-weight="700" font-family="'IBM Plex Mono',monospace" fill="#3A4552" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="${f(6)}">${dimTxt}</text>`
          + (FP_VISTA_LIMPIA ? '' : `<text x="${labelX}" y="${labelY+18*k}" font-size="${f(23)}" font-weight="700" font-family="'IBM Plex Mono',monospace" fill="#3A4552" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="${f(6)}">${areaTxt}</text>`)
        : `<text x="${labelX}" y="${labelY}" font-size="${f(30)}" font-weight="700" letter-spacing="0.5" font-family="'IBM Plex Sans',sans-serif" fill="#1C2530" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="${f(6)}">${label}</text>`;
      overlays.push(`<g class="fp-roomlabel" data-room-idx="${idx}" style="cursor:grab;">${labelLines}</g>`);
      // Auto-detected sub-areas (closet/laundry alcoves): name + own
      // dimensions, the way a pro plan annotates them. Tappable to
      // rename in Edit Plan.
      (room._subAreas||[]).forEach((sa, si) => {
        overlays.push(fpAnnotationLabelSvg(X, Y, 'fp-subarea',
          `data-room-idx="${idx}" data-sub-idx="${si}"`, sa, sa.cx, sa.cy, sa.name, sa.w, sa.d));
      });
    });
    // Hand-named open spaces (AI Fix asks, the human answers): a label
    // with dimensions on an area no scanned room claims - annotation
    // only, honest that no geometry was invented there.
    (data._spaceLabels||[]).forEach((sp, si) => {
      if(level != null && (sp.level||1) !== level) return;
      overlays.push(fpAnnotationLabelSvg(X, Y, 'fp-spacelabel',
        `data-space-idx="${si}"`, sp, sp.x, sp.y, sp.name, sp.w, sp.d));
    });
    // Paint layer: on the FLOOR PLAN this is the damage-brush strokes;
    // in MOISTURE MAP mode it is the moisture fills + strokes instead -
    // the two documents never mix layers.
    const floorNumForWater = level != null ? level : ((rooms[0] && rooms[0].level) || 1);
    let legendKinds = [], legendDefs = FP_BRUSH_KINDS;
    if(fpRenderMode === 'moisture'){
      legendDefs = FM_KINDS;
      s += '<g class="fp-water-layer">';
      const usedK = new Set();
      (data._moistureMarks||[]).forEach((m, mi) => {
        if((m.level||1) !== floorNumForWater) return;
        const kd = fmKindDef(m.kind);
        if(m.type === 'fill'){
          const room2 = (data.rooms||[])[m.roomIdx];
          if(!room2 || room2.deleted) return;
          // An adjusted fill has its own corners; a fresh one covers the
          // room outline.
          const poly = m.corners && m.corners.length >= 3 ? m.corners : fpOrderedRoomPolygon(room2);
          if(!poly || poly.length < 3) return;
          const dPath = poly.map((p, i) => `${i ? 'L' : 'M'}${X(p.x).toFixed(1)},${Y(p.y).toFixed(1)}`).join(' ') + ' Z';
          s += `<path class="fm-fill" data-fm-idx="${mi}" data-room-idx="${m.roomIdx}" d="${dPath}" fill="${kd.color}" stroke="none"/>`;
          usedK.add(m.kind);
        }else if(m.points && m.points.length >= 2){
          const dPath = m.points.map((p, i) => `${i ? 'L' : 'M'}${X(p.x).toFixed(1)},${Y(p.y).toFixed(1)}`).join(' ');
          s += `<path d="${dPath}" fill="none" stroke="${kd.color}" stroke-width="${(m.widthFt||3)*scale}" stroke-linecap="round" stroke-linejoin="round"/>`;
          usedK.add(m.kind);
        }
      });
      s += '</g>';
      legendKinds = [...usedK];
    }else{
      const waterMarks = (data._waterMarks||[]).filter(m => (m.level||1) === floorNumForWater && m.points && m.points.length >= 2);
      s += '<g class="fp-water-layer">';
      waterMarks.forEach(m => {
        const kindDef = FP_BRUSH_KINDS[m.kind || 'water'] || FP_BRUSH_KINDS.water;
        const dPath = m.points.map((p, i) => `${i ? 'L' : 'M'}${X(p.x).toFixed(1)},${Y(p.y).toFixed(1)}`).join(' ');
        s += `<path d="${dPath}" fill="none" stroke="${kindDef.color}" stroke-width="${(m.widthFt||1.5)*scale}" stroke-linecap="round" stroke-linejoin="round"/>`;
      });
      s += '</g>';
      legendKinds = [...new Set(waterMarks.map(m => m.kind || 'water'))];
    }
    s += overlays.join('');
    if(!fpSheetExport){
      // One legend line per kind actually used on this floor.
      legendKinds.forEach((k, ki) => {
        const kd = legendDefs[k] || Object.values(legendDefs)[0];
        const ly = svgH - 88 - ki*22;
        s += `<g><rect x="16" y="${ly}" width="26" height="12" rx="6" fill="${kd.color}"/>`
          + `<text x="50" y="${ly+11}" font-size="15" font-weight="600" fill="${kd.legendColor}">${kd.legend} (drawn by hand)</text></g>`;
      });
      // "FLOOR N" tag bottom-left, the way professional plans sign each
      // sheet's level.
      const floorNum = floorNumForWater;
      // Clear of the scale bar. Both were hardcoded to the bottom-left with
      // baselines 10px apart under a 24px glyph, so "FLOOR 1" and the scale
      // bar's "5 ft" printed on top of each other at every zoom level.
      // The scale bar's text baseline is svgH-26; this sits above its
      // ascender with room to spare.
      // La PLANTA, no el numero del escaneo (18 sep 2026). Este sello solo se
      // ve en la pantalla — el papel lleva el suyo en la banda —, pero decia
      // "FLOOR 1" encima del dibujo de un sotano, que es la misma mentira.
      const sello = ((data && data._nivelBase) ? (fpPlantaDeNivel(data, floorNum) || '') : '') || ('FLOOR ' + floorNum);
      s += `<text x="16" y="${svgH-64}" font-size="24" font-weight="700" letter-spacing="1" font-family="'IBM Plex Sans',sans-serif" fill="#1C2530">${esc(sello.toUpperCase())}</text>`;
      s += fpTitleBlock(svgW, svgH, data);
    }
    if(!FP_VISTA_LIMPIA) s += fpCompassAndScale(svgW, svgH, scale);
    s += `</svg>`;
    return s;
  }
  function buildFloorplanSvgUnmerged(data, level){
    const onLevel = r => level == null || (r.level||1) === level;
    const rooms = (data.rooms||[]).filter(r => onLevel(r) && !r.deleted);
    if(!rooms.length) return '<p style="color:#888; padding:20px; text-align:center;">No data yet.</p>';
    let out = '';
    (data.rooms||[]).forEach((room, idx) => {
      if(!onLevel(room) || room.deleted) return;
      const label = esc(room.roomName || `Room ${idx+1}`);
      if(!(room.walls||[]).length){
        out += `<div style="margin-bottom:14px; color:#888; text-align:center;">${label}: no data.</div>`;
        return;
      }
      const b = floorplanRoomBounds(room);
      const pad = FP_VISTA_LIMPIA ? 1.0 : 3.0; // same clipped-dimension-text fix as the merged view
      const minX = b.minX-pad, minY = b.minY-pad, maxX = b.maxX+pad, maxY = b.maxY+pad;
      const w = Math.max(1, maxX-minX), h = Math.max(1, maxY-minY);
      const scale = 60;
      const svgW = w*scale, svgH = h*scale;
      const X = x => (x-minX)*scale;
      const Y = y => (y-minY)*scale;
      const areaTxt = fpRoomDisplayAreaSqFt(room).toFixed(1);
      out += `<div style="margin-bottom:14px;"><div style="font-weight:600; margin-bottom:4px;">${label} — ${areaTxt} sq ft</div>`;
      out += `<svg viewBox="0 0 ${svgW} ${svgH}" width="${svgW}" height="${svgH}" data-fp-minx="${minX}" data-fp-miny="${minY}" data-fp-scale="${scale}" data-fp-room-idx="${idx}" style="display:block; background:#fff;" xmlns="http://www.w3.org/2000/svg">`;
      out += fpDefs();
      if(!FP_VISTA_LIMPIA) out += `<rect x="1" y="1" width="${svgW-2}" height="${svgH-2}" fill="none" stroke="#dfe4ea" stroke-width="1"/>`;
      out += buildFloorplanRoomContent(room, idx, X, Y, scale);
      (room._subAreas||[]).forEach((sa, si) => {
        const sx = X(sa.cx), sy = Y(sa.cy);
        out += `<g class="fp-subarea" data-room-idx="${idx}" data-sub-idx="${si}" style="cursor:pointer;">`
          + `<text x="${sx}" y="${sy-9}" font-size="17" font-weight="700" letter-spacing="0.4" font-family="'IBM Plex Sans',sans-serif" fill="#3A4552" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="4">${esc(sa.name).toUpperCase()}</text>`
          + `<text x="${sx}" y="${sy+11}" font-size="15" font-weight="700" font-family="'IBM Plex Mono',monospace" fill="#5a6472" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="4">${fpFeetInches(sa.w)} x ${fpFeetInches(sa.d)}</text>`
          + `</g>`;
      });
      out += '<g class="fp-water-layer">';
      if(fpRenderMode === 'moisture'){
        (data._moistureMarks||[]).forEach((m, mi) => {
          if(m.roomIdx !== idx) return;
          const kd = fmKindDef(m.kind);
          if(m.type === 'fill'){
            const poly = m.corners && m.corners.length >= 3 ? m.corners : fpOrderedRoomPolygon(room);
            if(!poly || poly.length < 3) return;
            const dPath = poly.map((p, i) => `${i ? 'L' : 'M'}${X(p.x).toFixed(1)},${Y(p.y).toFixed(1)}`).join(' ') + ' Z';
            out += `<path class="fm-fill" data-fm-idx="${mi}" data-room-idx="${idx}" d="${dPath}" fill="${kd.color}" stroke="none"/>`;
          }else if(m.points && m.points.length >= 2){
            const dPath = m.points.map((p, i) => `${i ? 'L' : 'M'}${X(p.x).toFixed(1)},${Y(p.y).toFixed(1)}`).join(' ');
            out += `<path d="${dPath}" fill="none" stroke="${kd.color}" stroke-width="${(m.widthFt||3)*scale}" stroke-linecap="round" stroke-linejoin="round"/>`;
          }
        });
      }else{
        (data._waterMarks||[]).filter(m => m.roomIdx === idx && m.points && m.points.length >= 2).forEach(m => {
          const kindDef = FP_BRUSH_KINDS[m.kind || 'water'] || FP_BRUSH_KINDS.water;
          const dPath = m.points.map((p, i) => `${i ? 'L' : 'M'}${X(p.x).toFixed(1)},${Y(p.y).toFixed(1)}`).join(' ');
          out += `<path d="${dPath}" fill="none" stroke="${kindDef.color}" stroke-width="${(m.widthFt||1.5)*scale}" stroke-linecap="round" stroke-linejoin="round"/>`;
        });
      }
      out += '</g>';
      if(!FP_VISTA_LIMPIA) out += fpCompassAndScale(svgW, svgH, scale);
      out += `</svg></div>`;
    });
    return out;
  }
  function buildFloorplanSvg(data, level){
    return data.merged ? buildFloorplanSvgMerged(data, level) : buildFloorplanSvgUnmerged(data, level);
  }
  const two = n => String(n).padStart(2,'0');
  let FP_VISTA_LIMPIA = false;
  function fpKVista(label, dimTxt, rb, X, Y, lx, ly){ const w = 2 * Math.min(lx - X(rb.minX), X(rb.maxX) - lx) * 0.88, h = 2 * Math.min(ly - Y(rb.minY), Y(rb.maxY) - ly) * 0.8; const ancho = Math.max(0.64 * 30 * String(label).replace(/&[a-z#0-9]+;/g, 'x').length, 0.6 * 23 * String(dimTxt).length); return Math.max(0.5, Math.min(2.4, w / ancho, h / 70)); }
  export function ponerVista(limpia){ FP_VISTA_LIMPIA = !!limpia; fpSheetExport = !!limpia; }
export { buildFloorplanSvg, buildFloorplanSvgUnmerged, floorplanLevels, fpRoomDisplayAreaSqFt, fpDisplayTotalAreaSqFt, fpOrderedRoomPolygon, fpPolygonAreaSqFt, fpFeetInches, fpPlanMeasurements, fpRoomMeasurements, floorplanIsExteriorWall };
