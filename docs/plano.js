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
  function floorplanRectifyWalls(data){
    let straightened = 0;
    ((data && data.rooms) || []).forEach(room => {
      const walls = (room.walls||[]).filter(w => w.start && w.end);
      if(!walls.length) return;
      // Corner clustering via the shared fpBuildNodes (defined with the
      // editor engine, same 0.35ft radius): endpoints within tolerance
      // are ONE physical corner node; positions write back to every
      // endpoint at the end - a room literally cannot come apart.
      const { nodes, ends } = fpBuildNodes(walls.map(w => ({ wall: w, roomIdx: 0 })));
      const offAxisDeg = e => {
        const ang = Math.abs(Math.atan2(e.b.y-e.a.y, e.b.x-e.a.x)) * 180/Math.PI % 180;
        return Math.min(ang % 90, 90 - (ang % 90));
      };
      const horiz = e => Math.abs(e.b.y-e.a.y) <= Math.abs(e.b.x-e.a.x);
      const lenOf = e => Math.hypot(e.b.x-e.a.x, e.b.y-e.a.y);
      // Count what pass A will straighten BEFORE moving anything.
      ends.forEach(e => { const off = offAxisDeg(e); if(off > 0.05 && off <= 3) straightened++; });
      // Pass A: near-axis noise - consensus mean-snap, iterated until the
      // corner network stops moving (walls sharing corners tug on the same
      // nodes; averaging converges geometrically).
      for(let it = 0; it < 12; it++){
        let moved = 0;
        ends.forEach(e => {
          const off = offAxisDeg(e);
          if(off <= 0 || off > 3) return;
          if(horiz(e)){
            const y = (e.a.y + e.b.y)/2;
            if(Math.abs(e.a.y-y) > 1e-6 || Math.abs(e.b.y-y) > 1e-6){ e.a.y = y; e.b.y = y; moved++; }
          }else{
            const x = (e.a.x + e.b.x)/2;
            if(Math.abs(e.a.x-x) > 1e-6 || Math.abs(e.b.x-x) > 1e-6){ e.a.x = x; e.b.x = x; moved++; }
          }
        });
        if(!moved) break;
      }
      // Pass B: a SHORT (<=6ft) connector 3-25deg off-axis joined at both
      // ends to longer axis-aligned walls is a mis-measured square return
      // - the corner backed by the SHORTER neighbor (least evidence)
      // moves onto the other corner's line. Genuinely diagonal
      // architecture (a 45deg bay, a long angled wall) never matches.
      ends.forEach(e => {
        const off = offAxisDeg(e);
        if(off <= 3 || off > 25 || lenOf(e) > 6) return;
        const neighborAt = node => {
          let best = null;
          ends.forEach(o => {
            if(o === e) return;
            if((o.a === node || o.b === node) && offAxisDeg(o) <= 3 && (!best || lenOf(o) > lenOf(best))) best = o;
          });
          return best;
        };
        const nA = neighborAt(e.a), nB = neighborAt(e.b);
        if(!nA || !nB || lenOf(nA) <= lenOf(e) || lenOf(nB) <= lenOf(e)) return;
        const moveA = lenOf(nA) <= lenOf(nB);
        const mover = moveA ? e.a : e.b, anchor = moveA ? e.b : e.a;
        // TOPE (13 de septiembre): esta regla movía una esquina hasta
        // 6·sin 25° = 2.54 ft sin decir cuánto. Ahora, más de 0.75 ft no se
        // mueve solo: queda para el asistente de esquinas, que lo PROPONE
        // con la cifra en el botón. 0.75 conserva el caso aceptado en obra
        // (Master Bedroom: conector de 2.4 ft a 17.8°, 0.73 ft).
        const lateral = horiz(e) ? Math.abs(mover.y - anchor.y) : Math.abs(mover.x - anchor.x);
        if(lateral > FP_ESQ.reglaBTope) return;
        if(data) data._rectifiedMaxMoveFt = Math.max(data._rectifiedMaxMoveFt || 0, Math.round(lateral * 100) / 100);
        if(horiz(e)) mover.y = anchor.y; else mover.x = anchor.x;
        straightened++;
      });
      // Write node positions back to every endpoint they own.
      nodes.forEach(n => n.refs.forEach(p => { p.x = n.x; p.y = n.y; }));
      walls.forEach(w => { w.lengthFt = Math.round(Math.hypot(w.end.x-w.start.x, w.end.y-w.start.y)*100)/100; });
    });
    if(data) data._rectified = straightened;
    return straightened;
  }
  function floorplanRefineGeometry(data){
    // HARD GATE (audit-confirmed critical): unmerged rooms live in
    // INDEPENDENT coordinate frames - two rooms' walls overlapping in
    // those frames is pure coincidence, and "reconciling" them welded
    // unrelated physical walls together (up to 0.55ft displacement and
    // +30% room area on the insurance PDF, reproduced on real scans).
    // Cross-room refinement is only meaningful in one shared frame.
    if(data && data.merged === false){
      data._refinement = { snappedWalls: 0, snappedOpenings: 0, skipped: 'unmerged' };
      return data._refinement;
    }
    const rooms = ((data && data.rooms) || []).filter(r => !r.deleted && (r.walls||[]).length);
    const sameLevel = (a, b) => (a.level||1) === (b.level||1);
    let snappedWalls = 0, snappedOpenings = 0;
    // --- Shared-wall snapping ---
    for(let a=0; a<rooms.length; a++){
      for(let b=a+1; b<rooms.length; b++){
        if(!sameLevel(rooms[a], rooms[b])) continue; // floors never share a physical wall line
        (rooms[a].walls||[]).forEach(wa => {
          if(!wa.start || !wa.end) return; // malformed record - skip, never crash
          const dxA = wa.end.x-wa.start.x, dyA = wa.end.y-wa.start.y;
          const lenA = Math.hypot(dxA,dyA) || 1;
          const uxA = dxA/lenA, uyA = dyA/lenA;
          const nxA = -uyA, nyA = uxA;
          (rooms[b].walls||[]).forEach(wb => {
            if(!wb.start || !wb.end) return; // malformed record - skip, never crash
            const dxB = wb.end.x-wb.start.x, dyB = wb.end.y-wb.start.y;
            const lenB = Math.hypot(dxB,dyB) || 1;
            if(Math.abs((dxB/lenB)*uxA + (dyB/lenB)*uyA) < 0.98) return; // not parallel
            const offB = ((wb.start.x-wa.start.x)*nxA + (wb.start.y-wa.start.y)*nyA);
            if(Math.abs(offB) < 0.02 || Math.abs(offB) > 0.6) return; // already aligned, or not the same wall
            const proj = p => (p.x-wa.start.x)*uxA + (p.y-wa.start.y)*uyA;
            const b0 = proj(wb.start), b1 = proj(wb.end);
            const lo = Math.max(0, Math.min(b0,b1)), hi = Math.min(lenA, Math.max(b0,b1));
            if(hi - lo <= 1.0) return; // no meaningful overlap
            // Length-weighted mutual best-fit line: shift each wall along
            // the normal so both land on it.
            const target = offB * (lenB / (lenA + lenB));
            const shiftA = target, shiftB = target - offB;
            [wa.start, wa.end].forEach(p => { p.x += nxA*shiftA; p.y += nyA*shiftA; });
            [wb.start, wb.end].forEach(p => { p.x += nxA*shiftB; p.y += nyA*shiftB; });
            snappedWalls++;
          });
        });
      }
    }
    // --- Cross-room door/opening position snapping ---
    const snapPair = (listA, listB) => {
      (listA||[]).forEach(oa => {
        (listB||[]).forEach(ob => {
          if(!oa.position || !ob.position) return;
          const d = Math.hypot(oa.position.x-ob.position.x, oa.position.y-ob.position.y);
          if(d < 0.02 || d > 0.75) return;
          const mx = (oa.position.x+ob.position.x)/2, my = (oa.position.y+ob.position.y)/2;
          oa.position = {x:mx, y:my};
          ob.position = {x:mx, y:my};
          snappedOpenings++;
        });
      });
    };
    for(let a=0; a<rooms.length; a++){
      for(let b=a+1; b<rooms.length; b++){
        if(!sameLevel(rooms[a], rooms[b])) continue;
        snapPair(rooms[a].doors, rooms[b].doors);
        snapPair(rooms[a].openings, rooms[b].openings);
      }
    }
    if(data) data._refinement = { snappedWalls, snappedOpenings };
    return { snappedWalls, snappedOpenings };
  }
  function floorplanDetectSubAreas(data){
    // Every door/passage on the plan (any room's copy, windows excluded):
    // a U-shaped pocket with a DOOR inside it is a doorway vestibule you
    // walk through, not a closet (field case: the bathroom's entry nook
    // wore a "CLOSET" label right on top of the bathroom door).
    const doorPts = [];
    ((data && data.rooms) || []).forEach(r => {
      if(r.deleted) return;
      [].concat(r.doors||[], r.openings||[]).forEach(o => {
        if(!o._removed && o.position) doorPts.push({ x: o.position.x, y: o.position.y, level: r.level || 1 });
      });
    });
    ((data && data.rooms) || []).forEach(room => {
      const poly = fpOrderedRoomPolygon(room);
      const found = [];
      if(poly && poly.length >= 5){
        const roomArea = fpPolygonAreaSqFt(poly) || 1;
        const n = poly.length;
        for(let i = 0; i < n; i++){
          const A = poly[i], B = poly[(i+1)%n], C = poly[(i+2)%n], D = poly[(i+3)%n];
          const ab = {x: B.x-A.x, y: B.y-A.y}, bc = {x: C.x-B.x, y: C.y-B.y}, cd = {x: D.x-C.x, y: D.y-C.y};
          const lab = Math.hypot(ab.x, ab.y), lbc = Math.hypot(bc.x, bc.y), lcd = Math.hypot(cd.x, cd.y);
          if(lab < 1.2 || lbc < 1.8 || lcd < 1.2) continue;
          // AB perpendicular to BC, CD perpendicular to BC, AB opposite CD.
          const dotAbBc = (ab.x*bc.x + ab.y*bc.y)/(lab*lbc);
          const dotAbCd = (ab.x*cd.x + ab.y*cd.y)/(lab*lcd);
          if(Math.abs(dotAbBc) > 0.15 || dotAbCd > -0.85) continue;
          const depth = Math.min(lab, lcd), width = lbc;
          // Depth cap 5.5 (was 4.5): a real hallway closet in the field
          // measured 4.64ft deep and silently missed its label.
          if(depth < 1.2 || depth > 5.5 || width < 1.8 || width > 8) continue;
          const areaSqFt = depth * width;
          if(areaSqFt < 5 || areaSqFt > 32 || areaSqFt > roomArea * 0.3) continue;
          // Pocket center: midpoint of BC pushed half the depth back
          // toward the room body (the AB direction reversed).
          const cx = (B.x + C.x)/2 - (ab.x/lab) * depth/2;
          const cy = (B.y + C.y)/2 - (ab.y/lab) * depth/2;
          // The pocket's center must sit INSIDE the room - a U that
          // opens OUTWARD (the peninsula between two real alcoves
          // matches the same corner pattern) would put a label on the
          // building's exterior.
          if(!fpPointInPolygon({x: cx, y: cy}, poly)) continue;
          // The room's own label must not live inside this pocket (that
          // would mean the "pocket" IS the room).
          const anchor = floorplanLabelAnchor(room);
          if(Math.hypot(anchor.x - cx, anchor.y - cy) < Math.max(depth, width)/2) continue;
          // A door in or on the pocket = a doorway you pass through, not
          // a closet. (Real closets detect as OPEN alcoves - a closet
          // with a recorded door has a mouth wall and never forms the U.)
          const bcux = bc.x/lbc, bcuy = bc.y/lbc;   // along the mouth
          const abux = ab.x/lab, abuy = ab.y/lab;   // into the pocket
          const roomLevel = room.level || 1;
          // DÓNDE está la puerta decide (14-oct, su clóset real del Master Bedroom): una puerta en la BOCA
          // del rincón (donde se une al cuarto) es la puerta del clóset -> sigue siendo clóset. Una puerta
          // al FONDO o a un lado es un paso a otro cuarto -> vestíbulo, no clóset (el caso del baño).
          let puertaEnLaBoca = false;
          const hasDoor = doorPts.some(p => {
            if(p.level !== roomLevel) return false; // a door two floors up is irrelevant
            const rx = p.x - cx, ry = p.y - cy;
            const along = Math.abs(rx*bcux + ry*bcuy);
            const intoS = rx*abux + ry*abuy;            // + hacia el fondo, - hacia la boca
            const into = Math.abs(intoS);
            const dentro = along <= width/2 + 0.5 && into <= depth/2 + 0.5;
            if(dentro && intoS <= -depth/2 + 0.6 && along <= width/2 - 0.3){ puertaEnLaBoca = true; return false; }
            return dentro;
          });
          // The door veto exists to kill entry vestibules (you walk THROUGH
          // a doorway; it is not a closet). But a real closet with its own
          // door looks identical to it, and after a hand edit put a door at
          // the mouth of a real Master Bedroom closet this veto silently
          // deleted the pocket - and with it the name the tech had typed.
          // A pocket a human already named is not a guess to be overruled.
          const namedBefore = (room._subAreas||[]).some(q => q._renamed &&
            Math.hypot(q.cx - cx, q.cy - cy) <= Math.max(1.5, Math.max(width, depth)/2));
          if(hasDoor && !namedBefore) continue;
          // Honest guess: Laundry if a washer/dryer sits in the pocket.
          let name = 'Closet';
          (room.objects||[]).forEach(o => {
            if(o.category === 'washerDryer' && o.center && Math.hypot(o.center.x-cx, o.center.y-cy) <= Math.max(depth, width)) name = 'Laundry';
          });
          found.push({ name, cx: Math.round(cx*100)/100, cy: Math.round(cy*100)/100,
                       w: Math.round(width*100)/100, d: Math.round(depth*100)/100, _suggested: true, conPuerta: puertaEnLaBoca || undefined });
        }
      }
      // Dedupe overlapping detections (an alcove can match from both
      // walk directions, and a wide alcove can ALSO match a sub-span of
      // itself - a real bedroom closet drew "CLOSET" twice 2.2ft apart).
      // Larger detections win; anything whose rectangle mostly sits
      // inside an already-kept one is the same physical pocket.
      found.sort((a, b) => (b.w*b.d) - (a.w*a.d));
      const dedup = [];
      found.forEach(p => {
        const isDupOf = q => {
          if(Math.hypot(q.cx-p.cx, q.cy-p.cy) <= 1.5) return true;
          const ox = Math.max(0, Math.min(q.cx+q.w/2, p.cx+p.w/2) - Math.max(q.cx-q.w/2, p.cx-p.w/2));
          const oy = Math.max(0, Math.min(q.cy+q.d/2, p.cy+p.d/2) - Math.max(q.cy-q.d/2, p.cy-p.d/2));
          return (ox*oy) > 0.4 * Math.min(p.w*p.d, q.w*q.d);
        };
        if(!dedup.some(isDupOf)) dedup.push(p);
      });
      const prev = room._subAreas || [];
      const carried = dedup.map(p => {
        const old = prev.find(q => q._renamed && Math.hypot(q.cx-p.cx, q.cy-p.cy) <= 1.5);
        // La posicion y el tamano que le dio la mano viajan con el nombre.
        // Sin esto, mover el rotulo de un CLOSET duraba hasta el siguiente
        // dibujo: la deteccion lo reemplaza en cada render.
        return old ? Object.assign(p, { name: old.name, _renamed: true, _suggested: false,
          _offFt: old._offFt, _labelScale: old._labelScale }) : p;
      });
      // This assignment used to be unconditional, and it runs on EVERY
      // render - so the moment detection came back empty (a hand edit
      // changing the outline is enough), a name the tech had typed was
      // gone for good, with no warning and no undo entry, because this
      // is a render path and not fpCommitEdit. A named pocket now
      // survives its own detection failing.
      prev.filter(q => q._renamed).forEach(q => {
        if(!carried.some(p => Math.hypot(p.cx-q.cx, p.cy-q.cy) <= 1.5)) carried.push(q);
      });
      room._subAreas = carried;
    });
    fpReconocerClosets(data);
  }
  const FP_NOMBRE_GENERICO = /^\s*(|open space|space|espacio|room\s*\d*|cuarto\s*\d*|unknown|unnamed|area|área)\s*$/i;
  const FP_ES_RECAMARA = /bed\s*room|recamara|recámara|habitaci|dormitorio|master|nursery|guest/i;
  const FP_ES_PASILLO = /hall|pasillo|corridor|entry|foyer|entrada|landing/i;
  function fpTipoPorMuebles(objs){
    const cats = (objs || []).filter(o => o && !o._hidden).map(o => o.category);
    if(cats.some(c => c === 'toilet' || c === 'bathtub')) return 'bath';
    if(cats.includes('washerDryer')) return 'laundry';
    return null;
  }
  function fpReconocerClosets(data){
    if(!data || !Array.isArray(data.rooms)) return;
    const vivos = data.rooms.filter(r => r && !r.deleted && (r.walls || []).length >= 3);
    const poligonos = vivos.map(r => { try{ return fpOrderedRoomPolygon(r); }catch(e){ return null; } });
    const distAlPoligono = (p, pg) => {
      let m = Infinity;
      for(let i = 0, j = pg.length - 1; i < pg.length; j = i++){
        const a = pg[j], b = pg[i], dx = b.x - a.x, dy = b.y - a.y, L2 = dx*dx + dy*dy || 1;
        const t = Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / L2));
        m = Math.min(m, Math.hypot(p.x - (a.x + t*dx), p.y - (a.y + t*dy)));
      }
      return m;
    };
    // vecinos de una figura (lista de puntos del borde): los cuartos que comparten al menos ~1.5 ft de pared
    const vecinosDe = (borde, yo, nivel) => vivos.filter((r, i) => r !== yo && (r.level || 1) === nivel && poligonos[i] && poligonos[i].length >= 3
      && borde.filter(p => distAlPoligono(p, poligonos[i]) <= 1.0).length >= 3);
    const bordeDe = (pg) => { const out = []; for(let i = 0, j = pg.length - 1; i < pg.length; j = i++){ const a = pg[j], b = pg[i], L = Math.hypot(b.x - a.x, b.y - a.y); const n = Math.max(1, Math.round(L / 0.5)); for(let k = 0; k < n; k++) out.push({ x: a.x + (b.x - a.x) * k / n, y: a.y + (b.y - a.y) * k / n }); } return out; };
    const decide = (area, minDim, tipoMuebles, vecinos) => {
      if(tipoMuebles === 'bath') return vecinos.some(v => /master/i.test(v.roomName || '')) ? 'Master Bath' : 'Bathroom';
      if(tipoMuebles === 'laundry') return 'Laundry';
      if(!(area > 0)) return null;
      const daARecamaraOPasillo = vecinos.some(v => FP_ES_RECAMARA.test(v.roomName || '') || FP_ES_PASILLO.test(v.roomName || ''));
      if(area <= 45 && daARecamaraOPasillo) return 'Closet';
      if(minDim > 0 && minDim <= 3.6 && area <= 60 && daARecamaraOPasillo) return 'Closet';
      if(area <= 30) return 'Closet';
      return null;
    };
    // 1) cuartos escaneados sin nombre (o "Room 3")
    vivos.forEach((r, i) => {
      if(!FP_NOMBRE_GENERICO.test(r.roomName || '') || r._namedByVoice) return;
      const pg = poligonos[i]; if(!pg || pg.length < 3 || fpAiFragileOutline(r)) return;
      const b = floorplanRoomBounds(r), area = fpRoomDisplayAreaSqFt(r);
      const nombre = decide(area, Math.min(b.maxX - b.minX, b.maxY - b.minY), fpTipoPorMuebles(r.objects), vecinosDe(bordeDe(pg), r, r.level || 1));
      if(nombre){ r.roomName = nombre; r._nombreAuto = nombre; r._suggestedConfidence = r._suggestedConfidence || 'Medium'; }
    });
    // 2) espacios con nombre genérico que se le pusieron al plano (el "Open Space" junto al pasillo)
    (data._spaceLabels || []).forEach(sp => {
      if(!sp || !FP_NOMBRE_GENERICO.test(sp.name || '') || !(sp.w > 0 && sp.d > 0)) return;
      const pg = [{ x: sp.x - sp.w/2, y: sp.y - sp.d/2 }, { x: sp.x + sp.w/2, y: sp.y - sp.d/2 }, { x: sp.x + sp.w/2, y: sp.y + sp.d/2 }, { x: sp.x - sp.w/2, y: sp.y + sp.d/2 }];
      const adentro = []; vivos.forEach(r => (r.objects || []).forEach(o => { if(o && o.center && Math.abs(o.center.x - sp.x) <= sp.w/2 && Math.abs(o.center.y - sp.y) <= sp.d/2) adentro.push(o); }));
      const nombre = decide(sp.w * sp.d, Math.min(sp.w, sp.d), fpTipoPorMuebles(adentro), vecinosDe(bordeDe(pg), null, sp.level || 1));
      if(nombre){ sp.name = nombre; sp._nombreAuto = nombre; }
    });
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
      ? (fpVista()
        ? `<text x="${sx}" y="${sy + 11*k}" font-size="${(14*k).toFixed(1)}" font-weight="600" font-family="'IBM Plex Sans',sans-serif" fill="#1C2530" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="4">${fpPiesPulg(w)} x ${fpPiesPulg(d)}</text>`
          + `<text x="${sx}" y="${sy + 28*k}" font-size="${(14*k).toFixed(1)}" font-weight="400" font-family="'IBM Plex Sans',sans-serif" fill="#2c3642" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="4">${(w*d).toFixed(1)} sq ft</text>`
        : `<text x="${sx}" y="${sy + 11*k}" font-size="${(15*k).toFixed(1)}" font-weight="700" font-family="'IBM Plex Mono',monospace" fill="#5a6472" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="4">${fpFeetInches(w)} x ${fpFeetInches(d)}</text>`)
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
  let fpEstiloVista = true;
  function fpVista(){ return fpEstiloVista && !fpSheetExport && fpRenderMode !== 'moisture'; }
  function fpPiesPulg(ft){ const t = Math.round((+ft || 0) * 12); return `${Math.floor(t / 12)}' ${t % 12}"`; }
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
    // Su diseño (14-oct): el vidrio son DOS líneas finas dentro del corte de la pared.
    const q = 0.3;
    return `<polygon points="${c1} ${c2} ${c3} ${c4}" fill="#ffffff" stroke="#1C2530" stroke-width="1.8"/>`
      + `<line x1="${cx-dxPx+p.x*t*q}" y1="${cy-dyPx+p.y*t*q}" x2="${cx+dxPx+p.x*t*q}" y2="${cy+dyPx+p.y*t*q}" stroke="#1C2530" stroke-width="1.2"/>`
      + `<line x1="${cx-dxPx-p.x*t*q}" y1="${cy-dyPx-p.y*t*q}" x2="${cx+dxPx-p.x*t*q}" y2="${cy+dyPx-p.y*t*q}" stroke="#1C2530" stroke-width="1.2"/>`;
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
  function fpApplyCornerFix(data, ri, f, auto){
    const room = ((data && data.rooms) || [])[ri];
    if(!room || !f) return false;
    const largo = w => { w.lengthFt = Math.round(Math.hypot(w.end.x - w.start.x, w.end.y - w.start.y) * 100) / 100; };
    const mover = (w, punta, a, marca) => {
      const desde = { x: w[punta].x, y: w[punta].y };
      w[punta] = { x: a.x, y: a.y };
      largo(w);
      if(auto) w[marca] = { end: punta, from: desde, ft: Math.round(Math.hypot(a.x - desde.x, a.y - desde.y) * 100) / 100 };
      else w._geomEdited = true;
    };
    if(f.kind === 'corner'){
      mover(f.wallA, f.puntaA, f.vertex, '_cornerClosed');
      mover(f.wallB, f.puntaB, f.vertex, '_cornerClosed');
      return true;
    }
    if(f.kind === 'overshoot'){
      mover(f.wallA, f.puntaA, f.vertex, '_cornerTrimmed');
      mover(f.wallB, f.puntaB, f.vertex, '_cornerTrimmed');
      return true;
    }
    if(f.kind === 'skew'){
      // La esquina es UN nodo: se mueven todas las puntas que lo comparten,
      // no solo la pared torcida. Revision del 13 de septiembre: antes solo
      // se marcaba `f.wall` y sin destino, asi que Reopen no podia devolver
      // nada (borraba la marca y dejaba la esquina movida) y la pared
      // vecina que tambien se corrio se iba sin *, sin † y sin contar en el
      // resumen. Ahora CADA pared que toca el nodo lleva su marca, con
      // destino incluido, para que Reopen sepa a donde volver.
      const refs = f.nodo.refs;
      const desde = { x: f.nodo.x, y: f.nodo.y };
      const destino = { x: f.destino.x, y: f.destino.y };
      refs.forEach(p => { p.x = destino.x; p.y = destino.y; });
      (room.walls || []).forEach(w => {
        if(!w.start || !w.end) return;
        if(refs.indexOf(w.start) < 0 && refs.indexOf(w.end) < 0) return;
        largo(w);
        if(auto){
          if(w === f.wall) w._cornerSquared = { from: desde, to: destino, ft: f.lateralFt };
          else w._cornerNodeMoved = { from: desde, to: destino, ft: f.lateralFt };
        }else{
          w._geomEdited = true;
        }
      });
      return true;
    }
    return false;
  }
  function floorplanCloseCorners(data){
    const cuenta = { closed: 0, squared: 0, trimmed: 0, maxMoveFt: 0 };
    if(!data || !data.rooms) return cuenta;
    (data.rooms || []).forEach((room, ri) => {
      if(!room || room.deleted) return;
      // Una a la vez y se vuelve a mirar: cerrar una esquina cambia el contorno.
      // Las que la usuaria ya reabrio (`_cornerAcks`, escrito por
      // fpReopenCorners) no se vuelven a cerrar solas: "despues ya no
      // vuelve a cerrarse sola" tiene que valer tambien cuando esto se
      // llama desde AI Fix, no solo al cargar el plano.
      const acks = room._cornerAcks || {};
      for(let vuelta = 0; vuelta < 8; vuelta++){
        const f = fpCornerFindings(data, ri).find(x => x.band === 'auto' && !acks[x.key]);
        if(!f || !fpApplyCornerFix(data, ri, f, true)) break;
        if(f.kind === 'corner') cuenta.closed++;
        else if(f.kind === 'skew') cuenta.squared++;
        else cuenta.trimmed++;
        cuenta.maxMoveFt = Math.max(cuenta.maxMoveFt, f.maxMoveFt || 0);
      }
    });
    const antes = data._corners || { closed: 0, squared: 0, trimmed: 0, maxMoveFt: 0 };
    data._corners = { closed: antes.closed + cuenta.closed, squared: antes.squared + cuenta.squared,
                      trimmed: antes.trimmed + cuenta.trimmed, maxMoveFt: Math.max(antes.maxMoveFt || 0, cuenta.maxMoveFt) };
    return cuenta;
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
    let out = `<polygon points="${fpPts(pts)}" fill="${fpVista() ? '#ffffff' : FLOORPLAN_FLOOR_FILL}"/>`;
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
  let fpRecorteN = 0;
  function fpRecorteDelCuarto(room, roomIdx, X, Y){
    try{
      if(!room || (room.walls || []).length < 3 || fpAiFragileOutline(room)) return null;
      const gap = {}; const poly = fpOrderedRoomPolygon(room, gap);
      if(!poly || poly.length < 3) return null;
      if((gap.bridgeSegs || []).some(b => b && b.d > 4)) return null;
      const id = 'fpcm' + roomIdx + '_' + (++fpRecorteN);
      return { id, defs: `<clipPath id="${id}"><polygon points="${fpPts(poly.map(p => ({ x: X(p.x), y: Y(p.y) })))}"/></clipPath>` };
    }catch(e){ return null; }
  }
  function buildFloorplanRoomContent(room, roomIdx, X, Y, scale, allRooms, buildingCentroid, overlays, drawnObjectKeys, skipFloorFill, capaMuebles){
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
    const iTrasPiso = s.length;   // aquí van los muebles: DEBAJO de las paredes (ver más abajo)

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
      // PAREDES UNIDAS (su diseño, 14-oct): cada pared es un rectángulo sobre su línea central, así que en
      // una esquina quedaba un mordisco de media pared por fuera. Un cuadro del grueso de la pared en cada
      // punta llena la esquina. Solo en una punta que de verdad lleva pared (si ahí empieza una puerta, el
      // hueco de la puerta se queda limpio).
      if(!stud){
        const wdx0 = wall.end.x - wall.start.x, wdy0 = wall.end.y - wall.start.y, wl0 = Math.hypot(wdx0, wdy0);
        if(wl0 > 0.05){
          const ux0 = wdx0 / wl0, uy0 = wdy0 / wl0, hh = FLOORPLAN_WALL_THICKNESS_FT / 2;
          [wall.start, wall.end].forEach(pt => {
            if(!segments.some(sg => Math.hypot(sg.start.x - pt.x, sg.start.y - pt.y) < 0.02 || Math.hypot(sg.end.x - pt.x, sg.end.y - pt.y) < 0.02)) return;
            const q4 = [[1,1],[1,-1],[-1,-1],[-1,1]].map(([a, b]) => ({ x: X(pt.x + ux0*hh*a - uy0*hh*b), y: Y(pt.y + uy0*hh*a + ux0*hh*b) }));
            s += `<polygon points="${fpPts(q4)}" fill="#1C2530" style="pointer-events:none;"/>`;
          });
        }
      }
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
      if(!fpVista() && effLen >= 0.25 && !seenNear('dim', midX, midY)){
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
      // La puerta de un clóset se dibuja corrediza (su pedido, 14-oct: "se ve más limpio" que el arco). Solo
      // cuando nadie escogió el tipo a mano (_doorStyle).
      const dDib = (!d._doorStyle && fpEsPuertaDeCloset(d, room, allRooms)) ? Object.assign({}, d, { _doorStyle: 'sliding' }) : d;
      s += fpDoorSwingMarkup(dDib, wallsById[d.wallId], centroid, X, Y);
      const cx = X(d.position.x), cy = Y(d.position.y);
      const dId = esc(String(d.id != null ? d.id : di));
      s += fpOpeningHitTarget('fp-door', roomIdx, dId, d, wallsById[d.wallId], X, Y);
      if(fpMeasurePrefs.openings && !fpVista()){
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
      if(fpMeasurePrefs.openings && !fpVista()){
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
      s += fpVista()
        ? `<line x1="${X(a.x)}" y1="${Y(a.y)}" x2="${X(b.x)}" y2="${Y(b.y)}" stroke="#5b6573" stroke-width="1.4"/>`   // su diseño: línea fina donde un cuarto pasa al otro
        : `<line x1="${X(a.x)}" y1="${Y(a.y)}" x2="${X(b.x)}" y2="${Y(b.y)}" stroke="#9aa3ad" stroke-width="2" stroke-dasharray="6,4"/>`;
    });

    // LOS MUEBLES NUNCA TAPAN UNA PARED (su pedido, 14-oct, con el plano real marcado): se dibujaban al
    // final, encima de todo, y un mueble pegado a la pared (gabinetes, la tina, una caja junto a la sala)
    // la cortaba o la hacía ver delgada. Ahora van debajo de las paredes, y recortados a su cuarto para que
    // ninguno se asome por fuera del edificio.
    const sAntesMuebles = s; s = '';
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
    {
      let muebles = s; s = sAntesMuebles;
      if(muebles){
        const recorte = fpRecorteDelCuarto(room, roomIdx, X, Y);
        if(recorte) muebles = recorte.defs + `<g clip-path="url(#${recorte.id})">` + muebles + `</g>`;
        if(capaMuebles) capaMuebles.push(muebles);
        else s = s.slice(0, iTrasPiso) + muebles + s.slice(iTrasPiso);
      }
    }
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
  function fpHuecoDelNombre(room, c, todos){
    try{
      const sp = fpRoomSpanAt(fpOrderedRoomPolygon(room), c) || {};
      // Las paredes de los OTROS cuartos también cuentan: en el plano real una pared del cuarto de al lado
      // cruzaba el hueco del Hallway y el nombre quedaba encima de ella.
      // Se mide toda la franja que ocupa el nombre (su alto, ~1 ft arriba y abajo), no una sola línea: en el
      // plano real la pared terminaba justo arriba de la línea y las letras le quedaban encima.
      const franja = [-1.0, -0.5, 0, 0.5, 1.0].map(k => c.y + k);
      (todos || []).forEach(r2 => (r2.walls || []).forEach(w => {
        if(!w || !w.start || !w.end) return;
        const ax = w.start.x, ay = w.start.y, bx = w.end.x, by = w.end.y;
        franja.forEach(yy => {
          if((ay - yy) * (by - yy) <= 0 && Math.abs(by - ay) > 1e-6){
            const x = ax + (yy - ay) * (bx - ax) / (by - ay);
            if(sp.h){ if(x < c.x && x > sp.h[0]) sp.h[0] = x; if(x > c.x && x < sp.h[1]) sp.h[1] = x; }
          }
        });
        if((ax - c.x) * (bx - c.x) <= 0 && Math.abs(bx - ax) > 1e-6){
          const y = ay + (c.x - ax) * (by - ay) / (bx - ax);
          if(sp.v){ if(y < c.y && y > sp.v[0]) sp.v[0] = y; if(y > c.y && y < sp.v[1]) sp.v[1] = y; }
        }
      }));
      if(!sp.h && !sp.v) return null;
      const T = FLOORPLAN_WALL_THICKNESS_FT;
      const w = sp.h ? 2 * Math.min(c.x - sp.h[0], sp.h[1] - c.x) - T : 0;
      const h = sp.v ? 2 * Math.min(c.y - sp.v[0], sp.v[1] - c.y) - T : 0;
      // Si en el punto del nombre no cabe, se corre al centro del hueco de pared a pared en esa misma
      // altura (sigue adentro del cuarto): wC es ese hueco entero.
      const wC = sp.h ? (sp.h[1] - sp.h[0]) - T : 0, xC = sp.h ? (sp.h[0] + sp.h[1]) / 2 : c.x;
      return { w: w > 0.5 ? w : 0, h: h > 0.5 ? h : 0, wC: wC > 0.5 ? wC : 0, xC };
    }catch(e){ return null; }
  }
  let fpEspaciosDelPlano = [];
  function fpEsPuertaDeCloset(d, room, todos){
    if(!d || !d.position) return false;
    const esCloset = n => /closet|closset|clóset/.test(String(n || '').toLowerCase());
    if(esCloset(room && room.roomName)) return true;
    const p = d.position;
    for(const r of (todos || [])){
      if(r === room || r.deleted) continue;
      if(esCloset(r.roomName)){
        const pg = fpOrderedRoomPolygon(r);
        if(pg && pg.length >= 3){
          if(fpPointInPolygon(p, pg)) return true;
          for(let i = 0, j = pg.length - 1; i < pg.length; j = i++){
            const a = pg[j], b = pg[i], dx = b.x - a.x, dy = b.y - a.y, L2 = dx*dx + dy*dy || 1;
            const t = Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / L2));
            if(Math.hypot(p.x - (a.x + t*dx), p.y - (a.y + t*dy)) <= 0.9) return true;
          }
        }
      }
    }
    // los espacios con nombre que se le pusieron al plano (un clóset que no se escaneó como cuarto aparte)
    for(const sp of (fpEspaciosDelPlano || [])){
      if(!esCloset(sp.name) || !(sp.w > 0)) continue;
      if(Math.abs(p.x - sp.x) <= sp.w / 2 + 0.9 && Math.abs(p.y - sp.y) <= sp.d / 2 + 0.9) return true;
    }
    for(const r of [room].concat(todos || [])){
      for(const sa of ((r && r._subAreas) || [])){
        if(!esCloset(sa.name) || !(sa.w > 0)) continue;
        if(Math.abs(p.x - sa.cx) <= sa.w / 2 + 0.9 && Math.abs(p.y - sa.cy) <= sa.d / 2 + 0.9) return true;
      }
    }
    return false;
  }
  function fpNombreClave(n){ return String(n || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, ' ').trim(); }
  function fpSpanEnLinea(room, P, todos, banda){
    const sp = fpRoomSpanAt(fpOrderedRoomPolygon(room), P) || {};
    let h = sp.h ? sp.h.slice() : null, v = sp.v ? sp.v.slice() : null;
    const ys = [P.y]; if(banda) for(let k = 0.5; k <= banda + 1e-9; k += 0.5){ ys.push(P.y - k, P.y + k); }
    (todos || []).forEach(r2 => (r2.walls || []).forEach(w => {
      if(!w || !w.start || !w.end) return;
      const ax = w.start.x, ay = w.start.y, bx = w.end.x, by = w.end.y;
      if(h) ys.forEach(yy => { if((ay - yy) * (by - yy) <= 0 && Math.abs(by - ay) > 1e-6){
        const x = ax + (yy - ay) * (bx - ax) / (by - ay);
        if(x < P.x - 0.05 && x > h[0]) h[0] = x; if(x > P.x + 0.05 && x < h[1]) h[1] = x;
      } });
      if(v && (ax - P.x) * (bx - P.x) <= 0 && Math.abs(bx - ax) > 1e-6){
        const y = ay + (P.x - ax) * (by - ay) / (bx - ax);
        if(y < P.y - 0.05 && y > v[0]) v[0] = y; if(y > P.y + 0.05 && y < v[1]) v[1] = y;
      }
    }));
    return { h, v };
  }
  function fpBloqueVista(room, label, areaTxt, rb, scale, X, Y, labelX, labelY, escala, libre, todos, minX, minY, movidoAMano){
    const T = FLOORPLAN_WALL_THICKNESS_FT;
    const letras = Math.max(4, String(label).replace(/&[a-z#0-9]+;/g, 'x').length);
    // 1. CENTRADO (su pedido): el bloque va al medio del cuarto, de pared a pared a lo largo y luego a lo ancho,
    // por la línea que pasa por el punto del nombre (siempre adentro del cuarto, aunque sea en L). Se compara
    // con el punto de siempre y gana donde el bloque se lee más grande sin tocar pared (en un cuarto raro, el
    // centro puede caer en un pasillo angosto). Un nombre que alguien movió a mano se queda donde lo dejó.
    // Todos los cuartos con la MISMA letra (su diseño): un tope parejo, y un cuarto chico (baño, clóset) más
    // chico en proporción — antes el tope dependía solo de lo que cabía y el baño salía más grande que la sala.
    const areaR = fpRoomDisplayAreaSqFt(room) || ((rb.maxX - rb.minX) * (rb.maxY - rb.minY));
    const tope = 0.56 * scale * (areaR > 0 && areaR < 80 ? Math.max(0.62, Math.sqrt(areaR / 80)) : 1);
    const evalua = (P) => {
      const sp = fpSpanEnLinea(room, P, todos);
      const largo = sp.h ? sp.h[1] - sp.h[0] : (rb.maxX - rb.minX), ancho = sp.v ? sp.v[1] - sp.v[0] : (rb.maxY - rb.minY);
      const dimTxt = `${fpPiesPulg(largo)} x ${fpPiesPulg(ancho)}`;
      // lo que cabe ALREDEDOR del punto (el doble de la distancia a la pared más cercana), no todo el tramo
      const sb = fpSpanEnLinea(room, P, todos, 1.0);   // el bloque mide ~2 ft de alto
      const libreW = Math.max(1, ((sb.h ? 2 * Math.min(P.x - sb.h[0], sb.h[1] - P.x) : largo) - T) * scale);
      const libreH = Math.max(1, ((sp.v ? 2 * Math.min(P.y - sp.v[0], sp.v[1] - P.y) : ancho) - T) * scale);
      const fit = Math.min(tope, (libreW * 0.84) / (0.66 * letras), (libreW * 0.84) / (0.6 * 0.74 * dimTxt.length), libreH * 0.2);
      return { P, sp, dimTxt, libreW, libreH, fit };
    };
    const P0 = { x: labelX / scale + minX, y: labelY / scale + minY };
    let mejor = evalua(P0);
    if(!movidoAMano){
      const Pc = { x: P0.x, y: P0.y };
      for(let i = 0; i < 2; i++){
        const a1 = fpSpanEnLinea(room, Pc, todos); if(a1.h) Pc.x = (a1.h[0] + a1.h[1]) / 2;
        const a2 = fpSpanEnLinea(room, Pc, todos); if(a2.v) Pc.y = (a2.v[0] + a2.v[1]) / 2;
      }
      const c2 = evalua(Pc);
      if(c2.fit >= mejor.fit * 0.95) mejor = c2;
    }
    const { P, sp, dimTxt, libreW, libreH } = mejor;
    const px = X(P.x); labelY = Y(P.y);
    // 2. tamaño: que quepan las tres líneas adentro, de pared a pared
    let fs = Math.max(0.34 * scale, mejor.fit) * Math.max(0.6, Math.min(2.2, escala || 1));
    const f2 = fs * 0.74, y0 = labelY - fs * 0.6;
    const t = (y, size, peso, color, txt, ls) => `<text x="${px.toFixed(1)}" y="${y.toFixed(1)}" font-size="${size.toFixed(1)}" font-weight="${peso}"${ls ? ` letter-spacing="${ls}"` : ''} font-family="'IBM Plex Sans',sans-serif" fill="${color}" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="${(size * 0.16).toFixed(1)}">${txt}</text>`;
    const svg = t(y0, fs, 700, '#1C2530', label, '0.6') + t(y0 + fs * 1.02, f2, 600, '#1C2530', dimTxt) + t(y0 + fs * 1.92, f2, 400, '#2c3642', areaTxt);
    // 4. puntitas de flecha, solo si hay lugar entre el bloque y la pared
    const a = Math.max(9, Math.min(15, 0.26 * scale)), dentro = T / 2 + 0.12;
    const tri = (x, y, dir) => {
      const pts = dir === 'l' ? `${x},${y} ${x + a},${y - a * 0.5} ${x + a},${y + a * 0.5}`
        : dir === 'r' ? `${x},${y} ${x - a},${y - a * 0.5} ${x - a},${y + a * 0.5}`
        : dir === 'u' ? `${x},${y} ${x - a * 0.5},${y + a} ${x + a * 0.5},${y + a}`
        : `${x},${y} ${x - a * 0.5},${y - a} ${x + a * 0.5},${y - a}`;
      return `<polygon points="${pts}" fill="#1C2530"/>`;
    };
    const anchoTxt = Math.max(0.66 * letras * fs, 0.6 * dimTxt.length * f2);
    let flechas = '';
    // la flecha va en la pared; solo hace falta que entre el bloque y la pared quede aire
    if(sp.h && Math.min(px - X(sp.h[0] + dentro), X(sp.h[1] - dentro) - px) > anchoTxt / 2 + a + 10) flechas += tri(X(sp.h[0] + dentro), labelY, 'l') + tri(X(sp.h[1] - dentro), labelY, 'r');
    if(sp.v && Math.min(labelY - Y(sp.v[0] + dentro), Y(sp.v[1] - dentro) - labelY) > fs * 1.6 + a + 10) flechas += tri(px, Y(sp.v[0] + dentro), 'u') + tri(px, Y(sp.v[1] - dentro), 'd');
    return { svg, flechas };
  }
  function fpCadenasCotas(rooms, b, centro, X, Y, scale){
    const T = FLOORPLAN_WALL_THICKNESS_FT;
    const lados = { top: [], bottom: [], left: [], right: [] };
    let sueltas = '';
    const vistas = new Set();
    rooms.forEach(room => (room.walls || []).forEach(w => {
      if(!w || !w.start || !w.end) return;
      const dx = w.end.x - w.start.x, dy = w.end.y - w.start.y, L = Math.hypot(dx, dy);
      if(L < 0.4 || !floorplanIsExteriorWall(w, room, rooms)) return;
      const mx = (w.start.x + w.end.x) / 2, my = (w.start.y + w.end.y) / 2;
      if(Math.abs(dy) <= L * 0.035){
        (my < centro.y ? lados.top : lados.bottom).push([Math.min(w.start.x, w.end.x), Math.max(w.start.x, w.end.x)]);
      } else if(Math.abs(dx) <= L * 0.035){
        (mx < centro.x ? lados.left : lados.right).push([Math.min(w.start.y, w.end.y), Math.max(w.start.y, w.end.y)]);
      } else {
        const k = mx.toFixed(1) + ',' + my.toFixed(1);
        if(!vistas.has(k)){ vistas.add(k); sueltas += fpDimensionLine(w, centro, X, Y, fpPiesPulg(floorplanWallEffectiveLength(w))); }
      }
    }));
    const fs = Math.max(20, Math.min(34, 0.52 * scale));
    const tic = 0.32 * scale;
    let out = '<g class="fp-cadenas" style="pointer-events:none;" font-family="\'IBM Plex Sans\',sans-serif">';
    Object.keys(lados).forEach(lado => {
      const iv = lados[lado]; if(!iv.length) return;
      // Cortes: todas las puntas; un tramo se mide si alguna pared lo cubre.
      const pts = []; iv.forEach(([a, c]) => { pts.push(a, c); });
      pts.sort((p, q) => p - q);
      const cortes = []; pts.forEach(v => { if(!cortes.length || v - cortes[cortes.length - 1] > 0.15) cortes.push(v); });
      const tramos = [];
      for(let i = 0; i + 1 < cortes.length; i++){
        const a = cortes[i], c = cortes[i + 1], m = (a + c) / 2;
        if(c - a >= 0.4 && iv.some(([p, q]) => m >= p - 0.05 && m <= q + 0.05)) tramos.push([a, c]);
      }
      // Un pedacito de menos de 9" (la punta de una pared que asoma) no se mide solo: se suma al tramo de
      // al lado si están pegados, y si está suelto se deja (con sus de 5" el lado se llenaba de basura).
      for(let i = 0; i < tramos.length; i++){
        const [a, c] = tramos[i]; if(c - a >= 0.75) continue;
        const prev = tramos[i - 1], next = tramos[i + 1];
        if(prev && Math.abs(prev[1] - a) < 0.05 && (!next || Math.abs(next[0] - c) >= 0.05 || prev[1] - prev[0] <= next[1] - next[0])){ prev[1] = c; tramos.splice(i--, 1); }
        else if(next && Math.abs(next[0] - c) < 0.05){ next[0] = a; tramos.splice(i--, 1); }
        else { tramos.splice(i--, 1); }
      }
      if(!tramos.length) return;
      const horiz = lado === 'top' || lado === 'bottom';
      const fuera = 1.25 + T / 2;
      const linea = lado === 'top' ? b.minY - fuera : lado === 'bottom' ? b.maxY + fuera : lado === 'left' ? b.minX - fuera : b.maxX + fuera;
      const P = v => horiz ? { x: X(v), y: Y(linea) } : { x: X(linea), y: Y(v) };
      // Línea por cada tramo seguido (un hueco entre tramos deja la línea cortada, como su diseño).
      let ini = tramos[0][0], fin = tramos[0][1];
      const corridas = [];
      tramos.slice(1).forEach(([a, c]) => { if(a - fin < 0.05) fin = c; else { corridas.push([ini, fin]); ini = a; fin = c; } });
      corridas.push([ini, fin]);
      corridas.forEach(([a, c]) => { const A = P(a), C = P(c); out += `<line x1="${A.x.toFixed(1)}" y1="${A.y.toFixed(1)}" x2="${C.x.toFixed(1)}" y2="${C.y.toFixed(1)}" stroke="#1C2530" stroke-width="1.4"/>`; });
      const rayas = new Set(); tramos.forEach(([a, c]) => { rayas.add(a.toFixed(3)); rayas.add(c.toFixed(3)); });
      rayas.forEach(v => { const Q = P(+v); out += horiz
        ? `<line x1="${Q.x.toFixed(1)}" y1="${(Q.y - tic / 2).toFixed(1)}" x2="${Q.x.toFixed(1)}" y2="${(Q.y + tic / 2).toFixed(1)}" stroke="#1C2530" stroke-width="1.4"/>`
        : `<line x1="${(Q.x - tic / 2).toFixed(1)}" y1="${Q.y.toFixed(1)}" x2="${(Q.x + tic / 2).toFixed(1)}" y2="${Q.y.toFixed(1)}" stroke="#1C2530" stroke-width="1.4"/>`; });
      // Números afuera de la línea; si no caben en su tramo, se suben a una segunda fila (nunca encimados).
      let finFila = [-Infinity, -Infinity];
      tramos.forEach(([a, c]) => {
        const txt = fpPiesPulg(c - a), M = P((a + c) / 2);
        const largo = horiz ? txt.length * fs * 0.55 : fs * 1.05;
        const ini2 = (horiz ? M.x : M.y) - largo / 2;
        let fila = ini2 >= finFila[0] + 6 ? 0 : 1;
        finFila[fila] = ini2 + largo;
        const sep = fs * 0.45 + fila * fs * (horiz ? 1.15 : 3.4);
        if(lado === 'top') out += `<text x="${M.x.toFixed(1)}" y="${(M.y - sep).toFixed(1)}" font-size="${fs.toFixed(1)}" font-weight="600" fill="#1C2530" text-anchor="middle">${txt}</text>`;
        else if(lado === 'bottom') out += `<text x="${M.x.toFixed(1)}" y="${(M.y + sep + fs * 0.75).toFixed(1)}" font-size="${fs.toFixed(1)}" font-weight="600" fill="#1C2530" text-anchor="middle">${txt}</text>`;
        else if(lado === 'left') out += `<text x="${(M.x - sep).toFixed(1)}" y="${(M.y + fs * 0.35).toFixed(1)}" font-size="${fs.toFixed(1)}" font-weight="600" fill="#1C2530" text-anchor="end">${txt}</text>`;
        else out += `<text x="${(M.x + sep).toFixed(1)}" y="${(M.y + fs * 0.35).toFixed(1)}" font-size="${fs.toFixed(1)}" font-weight="600" fill="#1C2530" text-anchor="start">${txt}</text>`;
      });
    });
    return out + '</g>' + sueltas;
  }
  function fpMarcoVista(svgW, svgH, u, data, floorNum){
    const company = esc(($('#companyName') && $('#companyName').value) || 'Scanova360');
    const job = (data && data.job) || fpJobInfo();
    const quien = esc([job.client, job.address].filter(Boolean).join(' · '));
    const m = Math.round(u * 0.6), hH = u * 3.6, hF = u * 3.2;
    const lv = floorplanLevels(data);
    const iNivel = Math.max(0, lv.indexOf(floorNum));
    const nombreNivel = (data && data._nivelBase) ? (fpPlantaDeNivel(data, floorNum) || ('Floor ' + floorNum)) : ('Floor ' + floorNum);
    const hayDudosas = (data.rooms || []).some(r => !r.deleted && (r.level || 1) === floorNum && (r.walls || []).some(w => w.confidence === 'low'));
    let o = `<g class="fp-marco" style="pointer-events:none;" font-family="'IBM Plex Sans',sans-serif">`;
    o += `<rect x="${m}" y="${m}" width="${svgW - 2*m}" height="${svgH - 2*m}" fill="none" stroke="#8d96a2" stroke-width="1.5"/>`;
    // encabezado
    o += `<text x="${m + u}" y="${m + u * 1.55}" font-size="${(u * 1.05).toFixed(1)}" font-weight="700" letter-spacing="1.2" fill="#1C2530">${company.toUpperCase()}</text>`;
    if(quien) o += `<text x="${m + u}" y="${m + u * 2.75}" font-size="${(u * 0.78).toFixed(1)}" font-weight="500" fill="#4a5462">${quien}</text>`;
    o += `<text x="${svgW - m - u}" y="${m + u * 1.75}" font-size="${(u * 0.95).toFixed(1)}" font-weight="700" letter-spacing="1" fill="#8d96a2" text-anchor="end">DRAFT • FOR REVIEW</text>`;
    o += `<line x1="${m + u * 0.6}" y1="${m + hH}" x2="${svgW - m - u * 0.6}" y2="${m + hH}" stroke="#8d96a2" stroke-width="1.2"/>`;
    // pie: cinco casillas
    const yT = svgH - m - hF, yTxt = yT + hF * 0.56, ancho = svgW - 2*m;
    o += `<line x1="${m + u * 0.6}" y1="${yT}" x2="${svgW - m - u * 0.6}" y2="${yT}" stroke="#8d96a2" stroke-width="1.2"/>`;
    const cols = [0.2, 0.2, 0.2, 0.28, 0.12];
    const celdas = [
      `<tspan fill="#4a5462">Level:</tspan> <tspan font-weight="700">${esc(nombreNivel)}</tspan>`,
      `<tspan fill="#4a5462">Units:</tspan> <tspan font-weight="700">ft / in</tspan>`,
      `<tspan fill="#4a5462">Scale:</tspan> <tspan font-weight="700">Not to scale</tspan>`,
      null,
      `Page <tspan font-weight="700">${iNivel + 1}</tspan> of <tspan font-weight="700">${Math.max(1, lv.length)}</tspan>`,
    ];
    let x = m;
    cols.forEach((c, i) => {
      const w = ancho * c;
      if(i) o += `<line x1="${x}" y1="${yT + hF * 0.22}" x2="${x}" y2="${yT + hF * 0.82}" stroke="#8d96a2" stroke-width="1"/>`;
      if(celdas[i]) o += `<text x="${x + u * 0.9}" y="${yTxt}" font-size="${(u * 0.82).toFixed(1)}" fill="#1C2530">${celdas[i]}</text>`;
      else {
        o += `<text x="${x + u * 0.7}" y="${yT + hF * 0.42}" font-size="${(u * 0.62).toFixed(1)}" fill="#3a4452">Measurements from the LiDAR scan; verify before final export.</text>`;
        o += `<text x="${x + u * 0.7}" y="${yT + hF * 0.74}" font-size="${(u * 0.62).toFixed(1)}" fill="#3a4452">${hayDudosas ? 'Red dashed wall = verify measurement.' : 'Dimensions are wall-to-wall at the wall center.'}</text>`;
      }
      x += w;
    });
    return o + '</g>';
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
    const pad = 3.0;
    // Vista (su diseño, 14-oct): más margen a los lados para las cadenas de medidas, y arriba/abajo el alto
    // del encabezado y del pie del marco. Va dentro del margen en pies, así X()/Y() no cambian y el editor
    // sigue tocando donde debe.
    const vista = fpVista();
    const bEdif = { minX, minY, maxX, maxY };
    let padL = pad, padR = pad, padT = pad, padB = pad, vu = 0;
    if(vista){
      vu = Math.max(16, Math.min(34, (maxX - minX + 9) * FLOORPLAN_SVG_SCALE / 90));
      padL = padR = 4.6;
      padT = 3.3 + (vu * 3.6) / FLOORPLAN_SVG_SCALE;
      padB = 2.8 + (vu * 3.2) / FLOORPLAN_SVG_SCALE;
    }
    minX-=padL; minY-=padT; maxX+=padR; maxY+=padB;
    const w = Math.max(1, maxX-minX), h = Math.max(1, maxY-minY);
    const scale = FLOORPLAN_SVG_SCALE;
    const svgW = w*scale, svgH = h*scale;
    const totalSvgH = svgH + ((fpSheetExport || vista) ? 0 : FLOORPLAN_STAMP_HEIGHT);
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
    if(!fpSheetExport && !vista) s += `<rect x="1" y="1" width="${svgW-2}" height="${totalSvgH-2}" fill="none" stroke="#dfe4ea" stroke-width="1"/>`;
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
    // Muebles de TODOS los cuartos primero y luego las paredes de todos: así el mueble de un cuarto tampoco
    // tapa la pared del cuarto de al lado (los cuartos se dibujan uno tras otro).
    const capaMuebles = [];
    let paredes = '';
    fpEspaciosDelPlano = (data._spaceLabels || []).filter(sp => level == null || (sp.level || 1) === level);
    (data.rooms||[]).forEach((room, idx) => {
      if(!(room.walls||[]).length || !onLevel(room) || room.deleted) return;
      paredes += buildFloorplanRoomContent(room, idx, X, Y, scale, rooms, buildingCentroid, overlays, drawnObjectKeys, true, capaMuebles);
      // A manually-positioned label anchors at the PLAIN geometric
      // center plus its own saved offset - the learned bias only steers
      // rooms with no manual override (applying it under an override
      // made pinned labels silently drift as new corrections changed
      // the bias). Un-overridden rooms get floorplanSmartLabelAnchor:
      // the guaranteed-inside geometric center, nudged by the pattern
      // of past manual corrections. Wrapped in one draggable <g> so the
      // whole name/area/dimensions stack moves together.
      // Vista (su pedido, 14-oct): un nombre que se movió a mano con el dibujo de ANTES quedaba en una
      // esquina (el Master Bedroom real). En la vista solo cuenta lo que se movió en la vista misma.
      const offVale = room._labelOffsetPx && (!vista || room._labelVista);
      const c = offVale ? floorplanLabelAnchor(room) : floorplanSmartLabelAnchor(room);
      const labelOff = offVale ? room._labelOffsetPx : {dx:0, dy:0};
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
      const k = kAuto * (room._labelScale || 1);
      const f = v => (v*k).toFixed(1);
      // Room span markers (Measure toggle): ONLY small triangles, one
      // pointing at each wall the room runs to - no connecting lines
      // (field feedback: "just the small triangular... I don't need the
      // lines"). Each sits just INSIDE the room, clear of the black wall
      // body, so it reads plainly on the white floor. Viewer only; never
      // on the exported sheet, which stays a clean professional document.
      if(!fpSheetExport && !vista && fpMeasurePrefs.extents !== false && areaNum >= 20){
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
      const hueco = vista ? fpHuecoDelNombre(room, c, rooms) : null;
      if(hueco){ hueco.correr = !offVale; hueco.xPx = X(hueco.xC); }   // un nombre movido a mano no se corre
      const bloque = vista ? fpBloqueVista(room, label, areaTxt, rb, scale, X, Y, labelX, labelY, room._labelScale || 1, hueco, rooms, minX, minY, offVale) : null;
      if(bloque && bloque.flechas) overlays.push(`<g class="fp-extent" style="pointer-events:none;">${bloque.flechas}</g>`);
      const labelLines = vista ? bloque.svg : fpMeasurePrefs.roomArea
        ? `<text x="${labelX}" y="${labelY-48*k}" font-size="${f(30)}" font-weight="700" letter-spacing="0.5" font-family="'IBM Plex Sans',sans-serif" fill="#1C2530" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="${f(6)}">${label}</text>`
          + `<text x="${labelX}" y="${labelY-14*k}" font-size="${f(23)}" font-weight="700" font-family="'IBM Plex Mono',monospace" fill="#3A4552" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="${f(6)}">${dimTxt}</text>`
          + `<text x="${labelX}" y="${labelY+18*k}" font-size="${f(23)}" font-weight="700" font-family="'IBM Plex Mono',monospace" fill="#3A4552" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="${f(6)}">${areaTxt}</text>`
        : `<text x="${labelX}" y="${labelY}" font-size="${f(30)}" font-weight="700" letter-spacing="0.5" font-family="'IBM Plex Sans',sans-serif" fill="#1C2530" text-anchor="middle" paint-order="stroke" stroke="#fff" stroke-width="${f(6)}">${label}</text>`;
      overlays.push(`<g class="fp-roomlabel" data-room-idx="${idx}" style="cursor:grab;">${labelLines}</g>`);
      // Auto-detected sub-areas (closet/laundry alcoves): name + own
      // dimensions, the way a pro plan annotates them. Tappable to
      // rename in Edit Plan.
      // Sin nombres repetidos (su pedido, 14-oct): un rincón detectado con el MISMO nombre que su cuarto (un
      // cuarto que el personal llamó "Closet" con un rincón que la app también llamó closet) no se escribe dos veces.
      const nomCuarto = fpNombreClave(room.roomName);
      (room._subAreas||[]).forEach((sa, si) => {
        if(nomCuarto && fpNombreClave(sa.name) === nomCuarto) return;
        overlays.push(fpAnnotationLabelSvg(X, Y, 'fp-subarea',
          `data-room-idx="${idx}" data-sub-idx="${si}"`, sa, sa.cx, sa.cy, sa.name, sa.w, sa.d));
      });
    });
    s += capaMuebles.join('') + paredes;
    // Hand-named open spaces (AI Fix asks, the human answers): a label
    // with dimensions on an area no scanned room claims - annotation
    // only, honest that no geometry was invented there.
    (data._spaceLabels||[]).forEach((sp, si) => {
      if(level != null && (sp.level||1) !== level) return;
      // Un "espacio sin cuarto" que cae ADENTRO de un cuarto escaneado no es un espacio aparte: es un rótulo
      // suelto encima del nombre de ese cuarto (en el plano real, "LAUNDRY ROOM" encima del Master Bedroom).
      if(rooms.some(r => { const pg = fpOrderedRoomPolygon(r); return pg && pg.length >= 3 && !fpAiFragileOutline(r) && fpPointInPolygon({ x: sp.x, y: sp.y }, pg); })) return;
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
    if(vista) s += fpCadenasCotas(rooms, bEdif, buildingCentroid, X, Y, scale);
    if(!fpSheetExport){
      // One legend line per kind actually used on this floor.
      legendKinds.forEach((k, ki) => {
        const kd = legendDefs[k] || Object.values(legendDefs)[0];
        const ly = (vista ? Y(bEdif.maxY) + 1.6*scale + 30 : svgH - 88) - ki*22;
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
      if(vista){
        s += fpMarcoVista(svgW, svgH, vu, data, floorNum);
      } else {
        s += `<text x="16" y="${svgH-64}" font-size="24" font-weight="700" letter-spacing="1" font-family="'IBM Plex Sans',sans-serif" fill="#1C2530">${esc(sello.toUpperCase())}</text>`;
        s += fpTitleBlock(svgW, svgH, data);
      }
    }
    if(!vista) s += fpCompassAndScale(svgW, svgH, scale);
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
      const pad = 3.0; // same clipped-dimension-text fix as the merged view
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
      out += `<rect x="1" y="1" width="${svgW-2}" height="${svgH-2}" fill="none" stroke="#dfe4ea" stroke-width="1"/>`;
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
      out += fpCompassAndScale(svgW, svgH, scale);
      out += `</svg></div>`;
    });
    return out;
  }
  function buildFloorplanSvg(data, level){
    return data.merged ? buildFloorplanSvgMerged(data, level) : buildFloorplanSvgUnmerged(data, level);
  }
  export function ponerVista(limpia){ fpEstiloVista = !!limpia; fpSheetExport = false; }
export { buildFloorplanSvg, buildFloorplanSvgUnmerged, floorplanLevels, fpRoomDisplayAreaSqFt, fpDisplayTotalAreaSqFt, fpOrderedRoomPolygon, fpPolygonAreaSqFt, fpFeetInches, fpPlanMeasurements, fpRoomMeasurements, floorplanIsExteriorWall, floorplanAlignRooms, floorplanRectifyWalls, floorplanRefineGeometry, floorplanCloseCorners, floorplanDetectSubAreas, fpReconocerClosets };
