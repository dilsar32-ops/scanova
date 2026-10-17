#!/bin/bash
# FASE 2 DE LA CAMARA NUEVA (15 oct 2026): la pantalla en estilo claro, DETRAS DE LA BANDERA.
# Lo que no se puede romper: sin la bandera (Field Reports hoy) la camara es exactamente la de siempre, y la
# pantalla nueva no inventa logica de medir: cada boton llama a la MISMA funcion que el boton viejo o la voz.
# Uso:  bash tests/fase2_camara_test.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
# (16 oct) Corre desde las pruebas de Field Reports (tests/) o desde el repo de Scanova (tests/camara/): el Swift es el de
# junto a las pruebas; la página de Field Reports y "el Swift idéntico" se leen de Field Reports (FR_DIR).
if [ -f "$DIR/../ios/App/App/ARMeasureViewController.swift" ]; then RAIZ="$DIR/.."; else RAIZ="$DIR/../.."; fi
FR="${FR_DIR:-/Users/amilcargonzalez/Downloads/field-report-ios-app}"
if [ -n "$SCANOVA_DIR" ]; then SC="$SCANOVA_DIR"; elif [ -f "$RAIZ/docs/medidas.js" ]; then SC="$RAIZ"; else SC="$DIR/../../scanova"; fi
python3 - "$RAIZ" "$SC" "$FR" <<'PYEOF'
import io, sys, re
fr, sc, frreal = sys.argv[1], sys.argv[2], sys.argv[3]
rd = lambda p: io.open(p, encoding='utf-8').read()
v = rd(fr + '/ios/App/App/ARMeasureViewController.swift'); plg = rd(fr + '/ios/App/App/ARMeasurePlugin.swift')
web = rd(frreal + '/www/index.html'); med = rd(sc + '/docs/medidas.js')
p = f = 0
def ok(l, c):
    global p, f
    if c: p += 1; print("  ok  " + l)
    else: f += 1; print("  FALLA " + l)
def bloque(src, firma):
    i = src.index(firma); j = src.index('{', i); d = 0; k = j
    while True:
        c = src[k]
        if c == '{': d += 1
        elif c == '}':
            d -= 1
            if d == 0: break
        k += 1
    return src[i:k+1]
nueva = v[v.index('LA CÁMARA NUEVA, ESTILO CLARO'):]
# ---- sin bandera, nada cambia ----
ok("armar la pantalla nueva exige la bandera", 'guard experienciaNueva, !nueva.armada else { return }' in bloque(v, 'fileprivate func armarCamaraNueva'))
ok("pintarla también", 'guard experienciaNueva, nueva.armada else { return }' in bloque(v, 'fileprivate func pintarCamaraNueva'))
ok("y el cuadro por cuadro", 'guard experienciaNueva, nueva.armada else { return }' in bloque(v, 'fileprivate func tickCamaraNueva'))
ok("el selector viejo solo se cambia por el panel con la bandera", 'if experienciaNueva {' in bloque(v, 'private func abrirSelector'))
ok("la ayuda de la primera vez solo se salta con la bandera", 'if !experienciaNueva, !d.bool(forKey: Self.seenHelpKey)' in v)
ok("sin micrófono, la lista vieja solo se calla con la bandera", 'guard stage == .pickingMaterial, !experienciaNueva else { return }' in v)
ok("los avisos mudos se copian a la pantalla nueva solo con la bandera", 'if experienciaNueva { mostrarAvisoNuevo(text) }' in v)
ok("Field Reports NO manda la bandera (sigue con la cámara de siempre)", 'experiencia' not in web)
ok("Scanova SÍ la manda", "experiencia: EXPERIENCIA_CAMARA" in med and "EXPERIENCIA_CAMARA = 'nueva'" in med)
# ---- la maqueta solo existe en el simulador ----
i = plg.index('#if targetEnvironment(simulator)'); j = plg.index('#endif', i)
ok("la maqueta se arma SOLO en el simulador", 'abrirMaqueta' in plg[i:j] and plg.count('abrirMaqueta') == 2)
ok("la maqueta no arranca ARKit ni pide micrófono", 'if maqueta == 0 { sceneView.session.run(config) }' in v and 'guard maqueta == 0 else { return }' in bloque(v, 'private func pedirPermisoYEscuchar'))
ok("por defecto no hay maqueta", 'var maqueta: Int = 0' in v)
# ---- ni una lógica nueva de medir: los mismos caminos de siempre ----
ok("el botón blanco marca con addTapped", 'accionesPosibles().marcar { addTapped() }' in nueva)
ok("Deshacer va por undoTapped", 'accionesPosibles().deshacer { undoTapped() }' in nueva)
for f_ in ['addWidthTapped()', 'saveContinueTapped()', 'finishPathTapped()']:
    ok("el botón de la derecha usa " + f_, f_ in bloque(v, 'private func pintarMuelleNuevo'))
ok("el botón de la derecha decide con accionesPosibles()", 'let puede = accionesPosibles()' in bloque(v, 'private func pintarMuelleNuevo'))
ok("el cuarto se escoge por el mismo camino que la voz", '_ = contestar(.queCuarto, cuarto)' in nueva)
ok("la parte también", '_ = contestar(.queSeccion, clave)' in nueva)
ok("el nivel también", '_ = contestar(.queNivel, nivel)' in nueva)
ok("el material, como la lista de siempre", 'materialConfirmTapped()' in bloque(v, 'private func elegirMaterialNuevo'))
ok("contar piezas va por la pastilla de siempre (+1 / −)", 'tocarAccionVieja("mas")' in nueva and 'tocarAccionVieja("menos")' in nueva)
ok("con una medida a medias no se cambia de cuarto ni de parte", nueva.count('if medidaEnCurso { say("Primero guarde o cancele la medida que lleva."') >= 3)
# ---- lo que pidió él ----
ok("ningún 'Hasta 2 pies' (la regla ya no existe)", 'Hasta 2 pies' not in nueva and '2 pies o menos' not in nueva)
ok("nada de verde en la pantalla nueva", 'systemGreen' not in nueva)
ok("salir sin mandar se confirma dos veces", nueva.count('"Salir sin mandar"') >= 2)
ok("los paneles nunca pasan del 60% (la cámara se sigue viendo); solo '¿Qué sigue?' llega al 70%, porque ahí no se mide nada",
   "view.bounds.height * (p == .sigue ? 0.7 : 0.6)" in nueva)
ok("los cuadros de la última fila no se estiran (cuadrícula pareja)", 'la fila de abajo no se estira' in nueva)
# ---- su prueba en el teléfono (15 oct): el número tapaba lo que se mide, y ya no preguntaba la insulación ----
centro = bloque(v, 'private func armarCentroNuevo')
ok("el número y la pista van ARRIBA, debajo de la barra (no pegados a la mira)", 'n.columna.topAnchor.constraint(equalTo: n.barra.bottomAnchor' in centro
   and 'n.ficha.bottomAnchor.constraint(equalTo: n.mira.topAnchor' not in centro)
tj = bloque(v, 'private func pintarTarjetaNueva')
ok("al completar la medida sale la tarjeta del compañero (insulación, underlayment, pad, shoe molding)", 'completa && currentCompanion != nil' in tj)
ok("nada viene marcado (solo lo que ya contestó por voz)", 'marcado: n.contestoAntes == true' in tj and 'marcado: n.contestoAntes == false' in tj)
ok("Sí guarda CON el compañero", 'includeCompanion = true\n        guardarDesdeTarjeta()' in nueva)
ok("No guarda SIN el compañero", 'includeCompanion = false\n        guardarDesdeTarjeta()' in nueva)
ok("guardar es el mismo saveContinueTapped de siempre", 'saveContinueTapped()' in bloque(v, 'private func guardarDesdeTarjeta'))
ok("la pared de afuera / de adentro se explica en la tarjeta", 'Pared de afuera: casi siempre sí. Pared de adentro: no.' in tj)
ok("con la tarjeta arriba no hay muelle ni mira encima", 'n.muelle.isHidden = panel != nil || n.tarjetaVisible' in nueva and '!n.panel.isHidden || n.tarjetaVisible' in nueva)
# ---- 15 oct, segunda prueba: el ancho de otro color, y la voz ----
ok("la línea que se va arrastrando es AZUL en el ancho/alto y amarilla en el largo", 'stage == .measuringWidth || stage == .widthDone) ? Self.tema.lineaAncho : Self.tema.lineaLargo' in v
   and 'let colorVivo = colorDeLineaViva()' in bloque(v, 'private func updateLiveLine'))
ok("las bolitas del ancho también azules", 'let marker = addMarker(at: hit, color: Self.tema.lineaAncho)' in v)
ok("la bolita abre la ventana Voz", 'abrirPanelNuevo(.voz)' in bloque(v, '@objc fileprivate func orbitaNuevaTocada'))
pv = bloque(v, 'private func armarPanelVoz')
ok("la ventana Voz enseña qué voz suena, las de este teléfono para oír y escoger, y la velocidad", 'Está sonando' in pv and 'VozAsistente.disponibles()' in pv and 'ajustarRitmo' in pv)
ok("si solo hay voces básicas, dice cómo bajar la natural", 'VozAsistente.soloBasicas()' in pv and 'comoBajarUnaMejor' in pv)
# ---- 15 oct, cuarta prueba: la bolita roja (el oído se cortaba solo) y "¿qué sigue?" después de guardar ----
rt = bloque(v, 'private func reiniciarTareaVoz')
ok("una tarea de voz VIEJA (cancelada al reiniciar) ya no cuenta como micrófono caído", 'guard mia == self.generacionVoz else { return }' in rt and 'generacionVoz += 1' in rt)
ok("el 'no oí nada' del teléfono tampoco: se vuelve a escuchar sin bolita roja", 'if Self.esSoloSilencio(error)' in rt and '1110' in bloque(v, 'static func esSoloSilencio'))
ok("si la tarea termina sola, se vuelve a escuchar en seguida (no espera los 40 s)", 'if r.isFinal {' in rt)
ok("al guardar sale '¿Qué sigue?'", 'return .sigue' in bloque(v, 'private func panelQueToca'))
sg = bloque(v, 'private func armarPanelSigue')
ok("con otra igual, otro material, cambiar de parte, otro cuarto, otro nivel y terminar",
   all(x in sg for x in ['"Otra de \\(nombre)"', '"Otro material"', 'elegirParteNueva(s)', '"Otro cuarto"', '"Otro nivel"', '"Terminar y mandar"']))
ok("en '¿Qué material?' también se ven 'Cambiar de parte' y 'Otro cuarto' (no solo las migas)", '"Cambiar de parte"' in bloque(v, 'private func armarPanelMaterial'))
# ---- 15 oct, quinta prueba: alto o ancho, la insulación al corregir, y lo que dice el plano ----
ok("alto en la pared y en lo que va parado (backsplash, tile de regadera...); ancho en piso, techo y cubiertas",
   'section == "wall" || Self.materialesParados.contains' in v and '"Backsplash"' in v and 'let nombreAlto = segundaEsAlto ? "Alto" : "Ancho"' in v)
ok("la voz ya no dice 'sin alto' en el piso o el techo", 'sale sin alto y no se cobra' not in v and v.count('sale sin \\(segundaPalabra)') == 2)
ok("la tarjeta solo marca lo que CONTESTÓ de verdad (ya no un 'No' que nadie dijo)", 'if n.respuestasVistas != respuestasCompanero {' in tj or 'if n.respuestasVistas != respuestasCompanero {' in v)
ok("cada respuesta de verdad se cuenta (sí/no por voz, ponle/quítale, otra igual)", v.count('respuestasCompanero += 1') >= 7)
ok("Corregir la medida: al rehacerla vuelve a preguntar", 'if !completa { n.tarjetaOculta = false }' in v)
ok("y el Guardar de abajo, con compañero pendiente, abre la tarjeta en vez de guardar sin preguntar", 'accion = { [weak self] in self?.nueva.tarjetaOculta = false; self?.pintarCamaraNueva() }' in v)
sg = bloque(v, 'fileprivate func sugerenciaDelPlano')
ok("el plano SUGIERE afuera/adentro por el largo medido (y no adivina si hay de los dos)", 'tipos.count == 1' in sg and 'no tiene paredes de afuera' in sg)
ok("la sugerencia no guarda ni marca: solo resalta", '"Sí · con \\(nombreComp)", subSi, marcado: n.contestoAntes == true, sugerido: sugiereSi' in v)
ok("el puente recibe las paredes del plano", 'call.getObject("paredesPorCuarto")' in plg)
ok("Scanova le manda a la cámara las paredes del plano", 'experiencia: EXPERIENCIA_CAMARA, paredesPorCuarto' in med and 'AYUDA.paredes' in med)
# ---- 15 oct: ubicarse dentro del plano con el LiDAR ----
ok("la cámara junta las paredes verticales que ve el LiDAR (solo con plano y en la pantalla nueva)", 'p.alignment == .vertical' in v and 'guard experienciaNueva, !planoPorCuarto.isEmpty else { return }' in v)
# 16 oct: cada segundo; cada 0.4 s si está reubicando o la ubicación dejó de confirmarse (arrancó 10 ft corrida y tardó 80 s).
ok("cada segundo se ubica contra el cuarto escogido (0.4 s si duda), y una dudosa no tumba una segura", 'Date().timeIntervalSince(n.ultimoUbicar) > intervalo' in v and 'let intervalo = (n.reubicandoDesde != nil || !n.firme || sinConfirmar > 4) ? 0.4 : 1.0' in v and 'if ac.seguro || !(n.acomodo?.seguro ?? false)' in v)
ok("las ventanas y puertas que reconoce el iPhone sirven de señas", 'case .window: clase = .ventana' in v and 'case .door: clase = .puerta' in v)
ok("la sugerencia usa primero la ubicación (sirve con cortes parciales) y luego el largo", v.index('UbicadorEnPlano.paredMedida(ac') < v.index('// 2. Sin ubicarse: por el largo'))
ok("el minimapa sale con cualquier plano (aunque haya un panel abierto), y dice cuando todavía no se ubica", 'guard !planoPorCuarto.isEmpty else { m.isHidden = true; n.columnaJuntoAlMapa?.isActive = false; return }' in bloque(v, 'private func pintarMinimapa') and 'n.panel.isHidden' not in bloque(v, 'private func pintarMinimapa') and '"Buscando paredes…"' in v)
ok("el puente recibe la forma de cada cuarto", 'call.getObject("planoPorCuarto")' in plg)
ok("Scanova le manda a la cámara la forma de cada cuarto", 'paredesPorCuarto, planoPorCuarto' in med)
# ---- 15 oct: PROBAR LO DEMOLIDO (laboratorio, solo manager) ----
lab = v[v.index('PROBAR LO DEMOLIDO (laboratorio, solo manager)'):]
ok("el botón de laboratorio exige la pantalla nueva Y la bandera laboratorio", 'guard experienciaNueva, laboratorio, !lab.armado else { return }' in bloque(v, 'fileprivate func armarBotonLaboratorio'))
ok("el puente solo lo prende si la página lo manda", 'arVC.laboratorio = call.getBool("laboratorio") ?? false' in plg)
ok("Field Reports NO manda el laboratorio", 'laboratorio' not in web)
ok("Scanova ya no manda el laboratorio (17-oct, él lo quitó)", 'laboratorio: false' in med)
ok("con el laboratorio abierto, la pantalla y el cuadro por cuadro de siempre no corren", 'if lab.activo { pintarLaboratorio(); return }' in bloque(v, 'fileprivate func pintarCamaraNueva') and 'if lab.activo { tickLaboratorio(); return }' in bloque(v, 'fileprivate func tickCamaraNueva'))
ok("el laboratorio NO guarda medidas (nunca llama a bancarMedida ni toca items)", 'bancarMedida' not in lab and 'items.append' not in lab and 'onFinish' not in lab)
ok("del cuadro de ARKit solo se COPIA (profundidad, confianza, pose) y el trabajo va en su propia fila", 'copiarProfundidad(prof.depthMap)' in lab and 'L.cola.async' in lab)
ok("la malla se apaga en el laboratorio y vuelve al salir", 'c.sceneReconstruction = .mesh' in bloque(v, 'private func salirLaboratorio'))
ok("el asistente se calla y deja de escuchar en el laboratorio, y vuelve como estaba", 'dejarDeEscuchar()' in bloque(v, 'fileprivate func entrarLaboratorio') and 'micApagadoPorElUsuario = L.micAntes' in bloque(v, 'private func salirLaboratorio'))
ok("con el teléfono muy caliente no se toman cuadros", 'guard termico != .critical' in lab)
ok("salir con grabaciones sin guardar pregunta antes de borrarlas", '¿Salir sin guardar la grabación?' in lab)
# ---- 15 oct: la ubicación se queda al cambiar de cuarto (mismo dibujo) ----
ub = bloque(v, 'fileprivate func ubicarseEnElPlano')
ok("la ubicación se borra al cambiar de NIVEL", 'if n.acomodoNivel != nivelActual { n.acomodoNivel = nivelActual; n.acomodo = nil; n.acomodoMarco = nil; n.calzas = []; n.puertaPared.soltar(); n.paredVista = nil }' in ub)
ok("al cambiar de cuarto SE QUEDA si es el mismo dibujo (y se espera mientras se escoge)", 'if n.acomodoCuarto != roomName, !roomName.isEmpty {' in ub and 'else if let m = marcoDe(roomName), m != n.acomodoMarco { n.acomodo = nil; n.acomodoMarco = nil }' in ub)
ok("con una página vieja (sin dibujo) se comporta como antes", 'if n.acomodoMarco == nil { n.acomodo = nil }' in ub)
ok("ya ubicado se afina contra TODA la planta, y solo acepta una respuesta segura y cerca", 'paredes: paredesPlanta' in ub and 'simd_length(ac.aplicar(c) - actual.aplicar(c)) < 2.0' in ub and '< 0.17' in ub)
ok("sabe en qué cuarto está (el más chico que lo rodea)", 'UbicadorEnPlano.rodea(p, $0.paredes)' in v)
ok("el minimapa enseña la planta entera y dice en qué cuarto está", 'm.otras = otras' in v and 'g.otras = otrasG' in v and '"✓ En \\(aqui)"' in v)
ok("el panel de cuartos marca AQUÍ", '"AQUÍ"' in bloque(v, 'private func armarPanelCuarto'))
ok("el puente recibe el dibujo de cada cuarto", 'marcos[cuarto] = Int(m)' in plg)
plan = rd(sc + '/docs/planos.js')
ok("Scanova manda el dibujo de cada cuarto (0 si el plano está juntado)", "marco: d.merged === false ? (d.rooms || []).indexOf(room) : 0" in plan)
# ---- 15 oct: PRIMERO UBICARSE (su prueba: "el mapa me sacaba hasta afuera") ----
fz = bloque(v, 'fileprivate func pintarFaseUbicarse')
ok("al abrir con plano, lo primero es la fase de ubicarse", 'nueva.ubicandose = !planoPorCuarto.isEmpty && maqueta == 0' in bloque(v, 'private func armarCamaraNueva'))
ok("en la fase solo se ve la mira y el plano grande (ni botones, ni muelle, ni panel)", 'for v in [n.columna, n.muelle, n.panel, n.tarjeta, n.minimapa, n.pista] { v.isHidden = true }' in fz and '"Buscando su ubicación"' in fz)
ok("la fase manda sobre la pantalla y el cuadro por cuadro de siempre", 'if nueva.ubicandose { pintarFaseUbicarse(); return }' in bloque(v, 'fileprivate func pintarCamaraNueva') and 'ubicarseEnElPlano()' in bloque(v, 'fileprivate func tickCamaraNueva') and 'pintarMinimapa(); pintarFaseUbicarse() }' in bloque(v, 'fileprivate func tickCamaraNueva'))
# 16 oct: un solo resolvedor, TODA la planta (antes primero el cuarto escogido: aceptaba ubicaciones que la casa no confirmaba).
ok("busca en toda la planta (y sin planta, en el cuarto escogido)", 'let paredes = paredesPlanta.isEmpty ? (forma?.paredes ?? []) : paredesPlanta' in ub)
ok("solo paredes de verdad para ubicarse (no muebles: sofá, gabinete, tina)", 'guard Self.esParedDeVerdad(p, pisoY: pisoMundo) else { descartados += 1; continue }' in ub and 'arriba - piso >= 1.9 && arriba - abajo >= 1.2' in v)
ok("reubicando, la misma ubicación rechazada no se acepta hasta ver algo nuevo (una pared nueva o 3 ft más)",
   'if ac.seguro, let rech = n.acomodoRechazado, !evidNueva, let c = cam,' in ub and 'rechazoHasta' not in v and 'n.planosAlTocar = Set(n.planosVistos.keys)' in v)
# ---- 16 oct, la revisión con la bitácora: reubicarse sola y no con los mismos datos ----
ok("reubicar a mano no corre con el laboratorio, y el laboratorio apaga la rueda",
   'guard !planoPorCuarto.isEmpty, n.reubicandoDesde == nil, !lab.activo else { return }' in bloque(v, 'fileprivate func reubicarAMano')
   and 'nueva.reubicandoDesde = nil; nueva.minimapa.ubicando = false' in bloque(v, 'fileprivate func entrarLaboratorio'))
ok("después de reubicarse se suelta lo que salió de la ubicación de antes (sin tocar lo guardado)", 'fileprivate func alReubicarse(salto: Double, porque: String)' in v)
ok("con lo firme, la de ahora solo se cambia si la casa la contradice (la lejana explica 4 o más)", 'let explica = !n.firme || (resp.map { $0.puntaje >= pAct + 4 } ?? false)' in ub)
ok("Ubicado pide además que crezca lo visto (no 3 respuestas con los mismos planos)", 'n.coincidencias >= 3 && n.ubicadoDesde == nil && crecio && ac.puntaje >= 8' in ub)
ok("sin confirmar hace rato el letrero lo dice (gris)", 'else if !ubicacionReciente() { m.ponerEstado("Sin confirmar", color: Claro.gris, reubicar: true) }' in v)
ok("con calor se apaga la malla del láser y al salir del laboratorio no se vuelve a prender", 'if !nueva.mallaApagada, ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { c.sceneReconstruction = .mesh }' in bloque(v, 'private func salirLaboratorio'))
ok("los cuadros lentos no cuentan las capturas, y la fase de ubicarse se anota", 'if dt < 1.0 {' in bloque(v, 'fileprivate func tickCamaraNueva') and 'anotarMedir("fase"' in v)
ok("una respuesta que pone el teléfono AFUERA de la casa no vale", 'UbicadorEnPlano.dentroDeLaCasa(ac.aplicar(c)' in ub and 'ac.seguro = false' in ub)
ok("se dice Ubicado solo con 3 respuestas seguidas en el mismo lugar (1 ft, 0.1 rad)", 'n.coincidencias >= 3 && n.ubicadoDesde == nil' in ub and '< 1.0' in ub and '< 0.1' in ub)
ok("ya ubicado se afina con todas las paredes vistas, sin brincar", 'UbicadorEnPlano.afinar(mejor, paredes: paredesPlanta, vistos: vistos)' in ub)
ok("Ubicado: dice en qué cuarto está y a los 1.5 s sale lo demás", '"✓ Ubicado"' in fz and 'Date().timeIntervalSince(desde) > 1.5 { terminarFaseUbicarse() }' in fz)
ok("se puede medir sin ubicarse (loseta con esquinas, no pastilla)", 'LosetaCamara(icono: "ruler", titulo: "Medir sin ubicarse"' in bloque(v, 'private func armarFaseUbicarse') and 'rejilla([saltar], columnas: 1)' in bloque(v, 'private func armarFaseUbicarse'))
ok("el minimapa va ARRIBA, debajo de la barra", 'm.topAnchor.constraint(equalTo: nueva.barra.bottomAnchor, constant: 10)' in bloque(v, 'private func armarMinimapa'))
ok("sin escoger cuarto el minimapa dibuja la planta (el dibujo no exige el cuarto)", '!(paredes.isEmpty && otras.isEmpty)' in v)
# ---- 16 oct: el laboratorio de lo demolido CON la ubicación (su "conéctalo a la cámara") ----
tl = bloque(v, 'fileprivate func tickLaboratorio')
ok("con la ubicación, el laboratorio escoge solo la pared del plano (un segundo apuntando)", 'apuntarParedDelPlano(frame, ac: ac)' in tl and 'Date().timeIntervalSince(ap.desde) >= 1.0' in v)
ok("solo con una ubicación segura y de este nivel", 'ac.seguro, nueva.acomodoNivel == nivelActual' in bloque(v, 'fileprivate func acomodoDeUbicacion') and 'acomodoDeUbicacion()' in bloque(v, 'fileprivate func acomodoParaLab'))
ok("primero las paredes del cuarto donde está (la compartida está en los dos)", '(lab.cuartoMalla ?? cuartoDondeEsta())?.lowercased()' in bloque(v, 'private func apuntarParedDelPlano'))
ok("el comparador recibe las esquinas, las puertas y las ventanas de esa pared", 'L.comparador.resultado(limites: lim, ventanas: ctx?.ventanas ?? [], puertas: ctx?.puertas ?? [])' in tl)
ok("las esquinas se afinan cada segundo con los planos de las paredes de al lado", 'DemolicionEnPlano.esquinas(cara, pared: ctx.pared, acomodo: ac, otros: otros)' in bloque(v, 'private func actualizarEsquinas'))
ok("dice el corte desde la esquina de la izquierda, como en el plano", 'desdeLaIzquierda: true' in tl and '"la esquina izq."' in v)
ok("dice qué falta ver de la pared", 'Falta ver de' in v)
ok("sin plano o sin ubicarse sigue el Fijar pared de siempre; con plano, a mano solo si la pared no está en el plano", '"Fijar pared", marcada: true' in v and 'if L.paredDesconocida { loseta("scope", "Fijar a mano")' in v)
ok("la ubicación sigue afinándose durante la prueba y el mapita marca la pared y el corte", 'ubicarseEnElPlano(); pintarMinimapa()' in tl and 'm.resaltada = (ctx.pared.a, ctx.pared.b)' in v)
ok("la grabación lleva la pared del plano (para repetirla en la Mac)", '"evento": "pared-plano"' in v)
ok("el puente lee el ancho de puertas y ventanas (4o número)", 'ancho: x.count >= 4' in plg)
ok("Scanova manda el ancho de cada puerta y ventana", 'x._widthOverrideFt || x.widthFt' in plan)
# ---- 15 oct: el TECHO en el laboratorio ("ahora pruébela para el techo") ----
ok("mirando para arriba (más de 30°) se apunta al techo", 'if adelante.y > 0.5 { apuntarTechoDelPlano(frame, ac: ac); return }' in v)
ok("el techo es el plano horizontal ARRIBA del teléfono, del cuarto donde está, un segundo apuntando", 'worldTransform.columns.3.y > camY + 0.4' in bloque(v, 'private func apuntarTechoDelPlano') and 'cuartoDondeEsta()' in bloque(v, 'private func apuntarTechoDelPlano'))
ok("el techo usa su propio comparador y sus límites salen de las paredes del cuarto", 'L.comparadorTecho.votar(camara: camPos, puntos: pts, cara: tt.cara)' in v and 'DemolicionEnPlano.limitesDelTecho(cara, paredes: paredes, acomodo: ac, planos: planos)' in v)
ok("la tarjeta dice cada hueco: largo × ancho, SF, si llega a la pared, y lo visto del techo", '"\\nHueco \\(i + 1): ' in v and 'llega a la pared' in v and 'visto %.0f%%' in v)
ok("sin plano se puede fijar el techo a mano (sin paredes)", 'TechoDelLab(cuarto: nil, cara: ComparadorDeTecho.Cara.desde(punto: p, eje: derecha, telefono: tel), limites: nil, ac: nil)' in v)
ok("la grabación marca el techo para que la Mac no lo mezcle con la pared", 'evento: "fijar-techo"' in v and 'if que == "fijar-techo" { techo = true }' in rd(fr + '/ios/App/App/GrabadoraDeBarrido.swift'))
ok("el mapita dibuja los huecos del techo", 'lab.resultadoTecho.huecos.flatMap' in v)
# ---- 15 oct: tubos en el techo y LA MALLA DE LA CASA ----
techo = rd(fr + '/ios/App/App/ComparadorDeTecho.swift')
ok("en el techo, lo que está ARRIBA de la cara del drywall (tubo, ducto) es 'encima': ahí ya no hay drywall", 'tapado, encima }' in techo and 'if m > 1.2 && q75 > 1.5 { return .encima }' in techo)
ok("un tubo o ducto se cuenta solo con hueco de verdad a los dos lados (hasta 16 in) y nunca en la orilla", 'if e - b > 8 || (e - b > 3 && arriba * 2 < e - b)' in techo and 'where viga[k] && ancho[k]' in techo)
ok("la malla de la casa: cada pared del plano en la cámara, del piso al techo", 'pintarMallaDeLaCasa(frame)' in bloque(v, 'fileprivate func tickLaboratorio') and 'static func texturaDeMalla' in v)
ok("la pared compartida por dos cuartos es UNA malla", 'private func claveDeMalla' in v)
ok("lo quitado se queda pintado en la malla de su pared", 'L.cortesPorPared[clave] = MallaDelCuarto.mezclar(' in v and 'L.resultado.tramos.map' in bloque(v, 'fileprivate func pintarMalla'))
# LA MALLA POR CUARTO (16 oct, su prueba con dos fotos)
mc = rd(fr + '/ios/App/App/MallaDelCuarto.swift')
ok("la malla va solo en el cuarto donde está (y se va con él al cambiar)", 'cuartoDado ?? L.cuartoMalla' in bloque(v, 'fileprivate func pintarMalla') and 'seguirElCuarto(m, base: base, frame: frame)' in v and 'removeFromParentNode(); L.malla[k] = nil' in v)
ok("al cambiar de cuarto espera 0.8 s (en una puerta no brinca)", '>= 0.8' in bloque(v, 'private func seguirElCuarto'))
ok("la ubicación del cuarto se afina con las paredes que ve el láser", 'MallaDelCuarto.ajustar(' in bloque(v, 'private func afinarMalla') and 'static func giroPorDirecciones' in mc and 'static func movPorVotos' in mc)
ok("de cada pared cuenta el plano de más afuera (lo de delante es mueble)", 'EL DE MÁS AFUERA' in mc and ('arriba >= piso + 1.2' in bloque(v, 'private func vistasParaMalla') or 'arriba < piso + 1.2 { porque = "bajo" }' in bloque(v, 'private func vistasParaMalla')))
ok("la cocina de su prueba: vota lo que el plano tiene ENCIMA de la pared, y la cara de atrás dice dónde está", 'encima + 0.5' in mc and 'static func detrasDe' in mc)
ok("un plano que ya amarra otra pared (no en la misma línea) no amarra esta ni entra al ajuste", 'planoDeOtraPared(v.id, clave: item.clave)' in bloque(v, 'private func afinarMalla') and '!ajenas.contains($0.id)' in bloque(v, 'private func afinarMalla'))
ok("la pared amarrada va de frente con su plano y a lo largo con el ajuste", 'simd_dot(aj.paredes[i].a - o, ul)' in bloque(v, 'private func afinarMalla'))
ok("un toque en una esquina ya amarrada no se cree a la primera; el aviso dice lo que de verdad se movió", 'esquinaDudosa' in bloque(v, '@objc private func toqueLab') and 'func revisarLaEsquinaTocada' in v and 'la malla se mueve %.0f in' not in v)
ok("la tarjeta solo fija una pared cerca y de frente; se suelta al cambiar de cuarto o si no se ve", '2.45' in bloque(v, 'private func apuntarParedDelPlano') and 'func soltarParedSinMirar' in v and 'dejé de medir la pared de' in v)
ok("no se pega a la cara del cuarto de al lado (el lado de cada plano)", 'nueva.ladoPlano[p.identifier]' in v and 'static func deEsteLado' in mc)
ok("si el ajuste sale enorme no se cree (10° o 1.5 m)", 'static let maxGiro = 10.0' in mc and 'static let maxMov = 1.5' in mc)
ok("tocar una esquina la amarra; dos dedos acercan; dos toques regresan", 'MallaDelCuarto.esquinaCercana(' in bloque(v, '@objc private func toqueLab') and 'UIPinchGestureRecognizer' in bloque(v, 'private func ponerGestosLab') and 'numberOfTapsRequired = 2' in v)
ok("los toques no se roban los de la tarjeta ni del mapita", 'v.isDescendant(of: tapa)' in bloque(v, 'fileprivate func toqueEsDeLaCamara') and 'is UIControl' in bloque(v, 'fileprivate func toqueEsDeLaCamara'))
ok("con zoom la malla se hace de cuadritos de 3 in", 'px / 4' in bloque(v, 'static func texturaDeMalla') and 'z >= 1.8' in bloque(v, 'fileprivate func aplicarZoomLab'))
ok("las alturas de corte de 1, 2 y 4 ft en la malla", 'for pies in [1.0, 2.0, 4.0]' in bloque(v, 'static func texturaDeMalla'))
ok("la memoria de la casa: se guarda y al volver la malla ya la trae", 'malla-memoria.json' in v and 'cargarMemoriaDeLaCasa()' in bloque(v, 'fileprivate func pintarMalla') and 'anotarParedEnLaMemoria()' in bloque(v, 'private func otraPared'))
ok("la tele: lo visto hoy manda, lo de antes se queda donde no se vio", 'static func mezclar(viejos:' in mc)
ok("la malla del techo: el contorno del cuarto a la altura del techo, con sus huecos", 'pintarMallaDelTecho(cuarto: cuarto' in bloque(v, 'fileprivate func pintarMalla') and 'static func contorno(' in mc and 'static func texturaDelTecho' in v)
ok("cada pared que el láser confirma se amarra a su plano y se queda (no se mueve todo de una pieza)", 'L.fijas[k] = ParedFija(' in bloque(v, 'private func afinarMalla') and 'for i in lineas.indices where !lineas[i].fija' in v and 'f.malas >= 8' in v)
ok("la malla también escanea: lo que se ve a través de la pared es una abertura", 'vigilarAberturas(frame)' in v and 'struct Traspaso' in mc and 'L.aberturasVistas[p.k] = nuevas' in v)
ok("una abertura de más del 60% de la pared no cuenta (es la malla corrida)", '$0.t1 - $0.t0 <= 0.6 * largo' in v)
ok("la bitácora del laboratorio: resumen cada 2 s, eventos, al servidor por la página y al teléfono", 'func anotarBitacora(' in v and 'notifyListeners("bitacora"' in plg and 'bitacora/' in v)
ok("los huecos del techo se guardan en la memoria de la casa", '"techos": techos' in v and 'static func mezclarTecho(' in mc and 'anotarTechoEnLaMemoria(seguir: seguir)' in v)
ok("la malla se quita al salir del laboratorio", 'quitarMallaDeLaCasa()' in bloque(v, 'private func salirLaboratorio'))
ok("el puente lee el alto de cada pared (6o número) y Scanova lo manda", 'alto: w.count >= 6' in plg and 'Number(w.heightFt) || 0' in plan)
# ---- 15 oct: la malla no tapa puertas ni ventanas; el escáner guarda dónde empiezan ----
enc = rd(fr + '/ios/App/App/FloorPlanEncoder.swift')
ok("el escáner guarda a qué altura del piso empieza cada puerta y ventana (bottomFt)", 'd["bottomFt"]' in enc)
ok("la malla deja el hueco de cada puerta y ventana de su pared", 'g.clear(r)' in bloque(v, 'static func texturaDeMalla') and 'L.mallaAberturas[clave] = abs_' in v)
ok("una ventana de un escaneo viejo (sin antepecho guardado) se supone a 3 ft y va punteada", 'sena.abajo >= 0 ? sena.abajo : 3' in v and 'ab.estimada ? [6, 5] : []' in v)
ok("Scanova manda dónde empieza y el alto de cada abertura (5o y 6o número)", 'x.bottomFt == null ? -1 : Number(x.bottomFt)' in plan and 'abajo: x.count >= 5' in plg)
# ---- 16 oct: LA PARTE SALE DEL MOVIMIENTO (la bandera; primero solo el manager) ----
ok("el puente lee la bandera porMovimiento", 'arVC.porMovimiento = call.getBool("porMovimiento") ?? false' in plg)
ok("Scanova la manda solo para el manager", 'porMovimiento: esManager()' in med)
ok("Field Reports NO la manda", 'porMovimiento' not in web)
ok("sin ella no corre nada (por defecto apagada, y exige la cámara nueva y el recorrido)", 'var porMovimiento: Bool = false' in v
   and 'var parteSolaActiva: Bool { experienciaNueva && porMovimiento && esRecorrido && seccionesDisponibles.count >= 2 }' in v)
ok("el detector va en el cuadro por cuadro, antes de ubicarse", 'revisarParteQueApunta()\n        ubicarseEnElPlano()' in bloque(v, 'fileprivate func tickCamaraNueva'))
same_lab = all(rd(frreal + '/ios/App/App/' + n) == rd(sc + '/ios/App/App/' + n) for n in ['ComparadorDeDemolicion.swift', 'GrabadoraDeBarrido.swift', 'DemolicionEnPlano.swift', 'ComparadorDeTecho.swift', 'MallaDelCuarto.swift'])
ok("el comparador y la grabadora son idénticos en las dos apps", same_lab)
same = all(rd(frreal + '/ios/App/App/' + n) == rd(sc + '/ios/App/App/' + n) for n in ['ARMeasureViewController.swift', 'ARMeasurePlugin.swift'])
ok("el Swift es idéntico en las dos apps", same)
print("\n  %d pasan, %d fallan" % (p, f))
sys.exit(1 if f else 0)
PYEOF
