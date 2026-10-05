"use client";

import Link from "next/link";
import { type FormEvent, type KeyboardEvent, type PointerEvent, useRef, useState } from "react";
import type { AcademyAdminContent, AcademyAdminList, AcademyAdminResult, AcademyAdminResultHistory, AcademyAdminResults, AcademyCourse, AcademyLesson, AcademyQuestion } from "../lib/academy";
import { academyDate, academyGet, academyPost } from "../lib/academy-client";
import { HpsmDialog } from "./hpsm-dialog";

type Tab = "course" | "lessons" | "assessment" | "questions" | "results";
type QuestionDraft = { id?: number; body: string; kind: "multiple_choice" | "true_false"; explanation: string; weight: number; position: number; options: Array<{ label: string; correct: boolean }> };
const newQuestion: QuestionDraft = { body: "", kind: "multiple_choice", explanation: "", weight: 1, position: 0,
  options: [{ label: "", correct: true }, { label: "", correct: false }, { label: "", correct: false }] };

export function AcademyManagement({ initial, canViewResults, canAdjust, canReopen }: { initial: AcademyAdminList; canViewResults: boolean; canAdjust: boolean; canReopen: boolean }) {
  const [listing, setListing] = useState(initial);
  const [selected, setSelected] = useState<number | null>(null);
  const [content, setContent] = useState<AcademyAdminContent | null>(null);
  const [tab, setTab] = useState<Tab>("course");
  const [lessonDraft, setLessonDraft] = useState<Partial<AcademyLesson> | null>(null);
  const [questionDraft, setQuestionDraft] = useState<QuestionDraft | null>(null);
  const [results, setResults] = useState<AcademyAdminResults | null>(null);
  const [resultHistory, setResultHistory] = useState<{ id: number; data: AcademyAdminResultHistory } | null>(null);
  const [search, setSearch] = useState("");
  const [resultCourse, setResultCourse] = useState<number | null>(null);
  const [resultStatus, setResultStatus] = useState<number | null>(null);
  const [resultPage, setResultPage] = useState(1);
  const [questionPage, setQuestionPage] = useState(1);
  const [gradeAction, setGradeAction] = useState<{ kind: "grade" | "attempt"; result: AcademyAdminResult } | null>(null);
  const [confirmation, setConfirmation] = useState<"publish" | "unpublish" | "archive" | null>(null);
  const [reason, setReason] = useState("");
  const [score, setScore] = useState(70);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [dragging, setDragging] = useState<{ from: number; over: number } | null>(null);
  const dragRef = useRef<{ from: number; startY: number; moved: boolean } | null>(null);
  const course = content?.course ?? null;
  const selectedAssessment = content?.assessment;
  async function loadList(page = listing.page) { setListing(await academyGet<AcademyAdminList>("admin", { page })); }
  async function loadContent(id: number, page = questionPage) { setContent(await academyGet<AcademyAdminContent>("admin_content", { courseId: id, page })); }
  async function loadResults(page = resultPage, query = search, id = resultCourse, status = resultStatus) {
    setResults(await academyGet<AcademyAdminResults>("admin_results", { courseId: id, refId: status, page, search: query }));
  }
  async function showResultHistory(id: number) {
    setBusy(true); setError("");
    try { setResultHistory({ id, data: await academyGet<AcademyAdminResultHistory>("admin_result", { refId:id }) }); }
    catch (cause) { setError(message(cause)); }
    finally { setBusy(false); }
  }
  async function select(id: number) {
    setSelected(id); setTab("course"); setLessonDraft(null); setQuestionDraft(null); setQuestionPage(1);
    setBusy(true); setError("");
    try { await loadContent(id,1); } catch (cause) { setError(message(cause)); }
    finally { setBusy(false); }
  }
  async function mutate<T>(action: string, payload: Record<string, unknown>, after?: (result: T) => Promise<void>) {
    setBusy(true); setError(""); setNotice("");
    try {
      const result = await academyPost<T>(action, payload);
      await after?.(result);
      if (selected) await loadContent(selected);
      await loadList();
      setNotice("Alteração salva.");
      return result;
    } catch (cause) { setError(message(cause)); return null; }
    finally { setBusy(false); }
  }
  async function saveCourse(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const payload = { name: String(form.get("name") || "").trim(), short_description: String(form.get("short_description") || ""),
      description: String(form.get("description") || ""), category: String(form.get("category") || "Institucional"),
      cover_url: String(form.get("cover_url") || ""),
      sort_order: course?.sort_order ?? 0, required: form.get("required") === "on" };
    if (course) await mutate("update_course", { course_id: course.id, ...payload });
    else await mutate<AcademyCourse>("create_course", payload, async (created) => {
      setSelected(created.id); await loadContent(created.id,1); setTab("lessons");
    });
  }
  async function saveLesson(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!course) return;
    const form = new FormData(event.currentTarget);
    await mutate("save_lesson", { course_id: course.id, lesson_id: lessonDraft?.id ?? null,
      title: String(form.get("title") || ""), description: String(form.get("description") || ""),
      body: String(form.get("body") || ""), video_url: String(form.get("video_url") || ""),
      image_url: String(form.get("image_url") || ""), material_url: String(form.get("material_url") || ""),
      position: lessonDraft?.id ? content?.lessons.find((item) => item.id === lessonDraft.id)?.position ?? lessonDraft.position ?? 0
        : Math.max(0, ...(content?.lessons.map((item) => item.position) ?? [])) + 1,
      required: form.get("required") === "on", active: lessonDraft?.active ?? true }, async () => setLessonDraft(null));
  }
  async function moveLesson(fromId: number, overId: number) {
    if (!course || !content || busy || fromId === overId) return;
    const from = content.lessons.findIndex((item) => item.id === fromId);
    const over = content.lessons.findIndex((item) => item.id === overId);
    if (from < 0 || over < 0) return;
    const ordered = [...content.lessons];
    ordered.splice(over, 0, ordered.splice(from, 1)[0]);
    setContent({ ...content, lessons: ordered.map((item, index) => ({ ...item, position: index + 1 })) });
    setBusy(true); setError(""); setNotice("");
    try {
      await academyPost("reorder_lessons", { course_id: course.id, lesson_ids: ordered.map((item) => item.id) });
      await loadContent(course.id);
      setNotice("Ordem das aulas atualizada.");
    } catch (cause) { setContent(content); setError(message(cause)); }
    finally { setBusy(false); }
  }
  function lessonAtPointer(event: PointerEvent<HTMLButtonElement>) {
    const row = document.elementFromPoint(event.clientX, event.clientY)?.closest<HTMLElement>("[data-lesson-row]");
    const id = Number(row?.dataset.lessonRow);
    return content?.lessons.some((item) => item.id === id) ? id : null;
  }
  function startLessonDrag(event: PointerEvent<HTMLButtonElement>, id: number) {
    if (busy || (event.pointerType === "mouse" && event.button !== 0)) return;
    dragRef.current = { from: id, startY: event.clientY, moved: false };
    event.currentTarget.setPointerCapture(event.pointerId);
  }
  function trackLessonDrag(event: PointerEvent<HTMLButtonElement>) {
    const drag = dragRef.current;
    if (!drag || (Math.abs(event.clientY - drag.startY) < 5 && !drag.moved)) return;
    drag.moved = true;
    const over = lessonAtPointer(event);
    setDragging({ from: drag.from, over: over ?? drag.from });
  }
  function finishLessonDrag(event: PointerEvent<HTMLButtonElement>) {
    const drag = dragRef.current;
    const over = lessonAtPointer(event);
    dragRef.current = null; setDragging(null);
    if (drag?.moved && over !== null && over !== drag.from) void moveLesson(drag.from, over);
  }
  function keyboardLessonMove(event: KeyboardEvent<HTMLButtonElement>, id: number) {
    if (event.key !== "ArrowUp" && event.key !== "ArrowDown") return;
    event.preventDefault();
    const index = content?.lessons.findIndex((item) => item.id === id) ?? -1;
    const target = content?.lessons[index + (event.key === "ArrowUp" ? -1 : 1)];
    if (target) void moveLesson(id, target.id);
  }
  async function saveAssessment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!course) return;
    const form = new FormData(event.currentTarget);
    await mutate("save_assessment", { course_id: course.id, enabled: form.get("enabled") === "on",
      question_count: Number(form.get("question_count") || 5), passing_score: Number(form.get("passing_score") || 70),
      max_attempts: Number(form.get("max_attempts") || 3), shuffle_questions: form.get("shuffle_questions") === "on",
      shuffle_options: form.get("shuffle_options") === "on", reveal_policy: String(form.get("reveal_policy") || "after_final") });
  }
  async function saveQuestion(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!course || !questionDraft) return;
    const form = new FormData(event.currentTarget);
    await mutate("save_question", { course_id: course.id, question_id: questionDraft.id ?? null,
      body: String(form.get("body") || ""), kind: questionDraft.kind, explanation: String(form.get("explanation") || ""),
      weight: Number(form.get("weight") || 1), position: Number(form.get("position") || 0),
      options: questionDraft.options.map((option) => ({ label: option.label.trim(), correct: option.correct })) }, async () => setQuestionDraft(null));
  }
  async function changeTab(next: Tab) {
    setTab(next); setError("");
    if (next === "results" && canViewResults) {
      setBusy(true); try { await loadResults(1); } catch (cause) { setError(message(cause)); } finally { setBusy(false); }
    }
  }
  async function actGrade() {
    if (!gradeAction) return;
    const action = gradeAction.kind === "grade" ? "override_grade" : "grant_attempt";
    const result = await mutate(action, { enrollment_id: gradeAction.result.id, reason, ...(action === "override_grade" ? { score } : {}) }, async () => { await loadResults(); });
    if (result) { setGradeAction(null); setReason(""); setResultHistory(null); }
  }
  return <main className="academy-page academy-admin-page">
    <nav className="academy-breadcrumb"><Link href="/academia" prefetch={false}>Academia HPSM</Link><span>/</span><span>Gestão</span></nav>
    <header className="academy-heading"><div><span className="academy-eyebrow">DIRETORIA</span><h2>Cursos e avaliações</h2><p>Organize cursos e acompanhe o aprendizado da equipe.</p></div>
      <button className="academy-button" onClick={() => { setSelected(null); setContent(null); setTab("course"); setError(""); }}>Criar curso</button></header>
    {error ? <div className="academy-message error" role="alert">{error}</div> : null}{notice ? <div className="academy-message" role="status">{notice}</div> : null}
    <div className="academy-admin-summary"><span><strong>{listing.total}</strong> cursos</span><span><strong>{listing.courses.filter((item) => item.status === "published").length}</strong> publicados nesta página</span>
      <span><strong>{listing.courses.reduce((sum,item) => sum+(item.students ?? 0),0)}</strong> matrículas nesta página</span><span><strong>{listing.courses.reduce((sum,item) => sum+(item.approved ?? 0),0)}</strong> aprovações nesta página</span></div>
    <div className="academy-admin-layout"><aside className="academy-admin-list"><h2>Cursos</h2>{listing.courses.map((item) => <button key={item.id} className={selected === item.id ? "current" : ""} type="button" onClick={() => void select(item.id)}><strong>{item.name}</strong><small>{item.category} · {labelStatus(item.status)}</small></button>)}
      {!listing.courses.length ? <p>Nenhum curso cadastrado.</p> : null}
      {listing.total > 100 ? <div className="academy-pagination"><button disabled={busy || listing.page === 1} onClick={() => void loadList(listing.page-1)}>Anterior</button><span>{listing.page}</span><button disabled={busy || listing.page*100 >= listing.total} onClick={() => void loadList(listing.page+1)}>Próxima</button></div> : null}</aside>
      <section className="academy-admin-workspace">
        {course ? <><div className="academy-admin-title"><div><span className="academy-eyebrow">{labelStatus(course.status)}</span><h2>{course.name}</h2></div>
          <div className="academy-admin-actions"><Link className="academy-button academy-button-secondary" href={`/academia/${course.id}`} prefetch={false}>Visualizar</Link>
            {course.status !== "published" ? <button className="academy-button" onClick={() => setConfirmation("publish")}>Publicar</button> : <button className="academy-button academy-button-secondary" onClick={() => setConfirmation("unpublish")}>Despublicar</button>}
            {course.status !== "archived" ? <button className="academy-button academy-button-muted" onClick={() => setConfirmation("archive")}>Arquivar</button> : null}</div></div>
          <nav className="academy-tabs" aria-label="Gestão do curso">{(["course","lessons","assessment","questions",...(canViewResults ? ["results"] : [])] as Tab[]).map((item) => <button key={item} type="button" className={tab === item ? "current" : ""} onClick={() => void changeTab(item)}>{({ course:"Dados",lessons:"Aulas",assessment:"Avaliação",questions:"Questões",results:"Resultados" })[item]}</button>)}</nav></> : null}
        {tab === "course" ? <form key={course?.id ?? "new"} className="academy-form" onSubmit={(event) => void saveCourse(event)}><h3>{course ? "Editar curso" : "Novo curso"}</h3>
          <label>Título<input name="name" required minLength={2} maxLength={120} defaultValue={course?.name ?? ""} /></label>
          <label>Descrição curta<input name="short_description" maxLength={250} defaultValue={course?.short_description ?? ""} /></label>
          <label>Descrição completa<textarea name="description" rows={4} maxLength={4000} defaultValue={course?.description ?? ""} /></label>
          <label>Categoria<select name="category" defaultValue={course?.category ?? "Institucional"}>{["Institucional","Medicina","Enfermagem","Emergência","Exames","Farmacologia RP","Gestão","Procedimentos","Outros",...(course && !["Institucional","Medicina","Enfermagem","Emergência","Exames","Farmacologia RP","Gestão","Procedimentos","Outros"].includes(course.category) ? [course.category] : [])].map((item) => <option key={item}>{item}</option>)}</select></label>
          <label>URL da capa (opcional)<input name="cover_url" type="url" placeholder="https://" defaultValue={course?.cover_url ?? ""} /></label>
          <label className="academy-check"><input name="required" type="checkbox" defaultChecked={course?.required ?? false} />Curso obrigatório (indicação visual; sem vínculo à progressão)</label>
          <button className="academy-button" disabled={busy}>Salvar curso</button></form> : null}
        {course && content && tab === "lessons" ? <div className="academy-admin-block"><div className="academy-section-head"><h3>Aulas</h3><button className="academy-button academy-button-secondary" onClick={() => setLessonDraft({ title:"",description:"",body:"",required:true,active:true })}>Adicionar aula</button></div>
          {content.lessons.length > 1 ? <p className="academy-reorder-hint">Segure o ícone e arraste a aula para mudar a ordem.</p> : null}
          <div className="academy-admin-rows academy-sortable-lessons">{content.lessons.map((item, index) => <article key={item.id} data-lesson-row={item.id} data-dragged={dragging?.from === item.id} data-drop-target={dragging?.over === item.id && dragging.from !== item.id}>
            <button className="academy-reorder-handle" type="button" disabled={busy || content.lessons.length < 2} aria-label={`Mover ${item.title}. Arraste ou use as setas para cima e para baixo.`} onPointerDown={(event) => startLessonDrag(event, item.id)} onPointerMove={trackLessonDrag} onPointerUp={finishLessonDrag} onPointerCancel={() => { dragRef.current = null; setDragging(null); }} onKeyDown={(event) => keyboardLessonMove(event, item.id)}>⋮⋮</button>
            <div><strong>{index + 1}. {item.title}</strong><small>{!item.active ? "Inativa · " : ""}{item.required ? "Obrigatória" : "Opcional"}</small></div><button disabled={busy} onClick={() => setLessonDraft(item)}>Editar</button>
          </article>)}{!content.lessons.length ? <p>Adicione as aulas para publicar o curso.</p> : null}</div>
          {lessonDraft ? <form key={lessonDraft.id ?? "new"} className="academy-form academy-inline-form" onSubmit={(event) => void saveLesson(event)}><h3>{lessonDraft.id ? "Editar aula" : "Nova aula"}</h3><label>Título<input name="title" required minLength={2} maxLength={160} defaultValue={lessonDraft.title ?? ""} /></label>
            <label>Resumo<input name="description" maxLength={500} defaultValue={lessonDraft.description ?? ""} /></label>
            <label>Material da aula <small>(# título, ## subtítulo, **destaque**, - lista, [link](https://...))</small><textarea name="body" rows={9} maxLength={30000} defaultValue={lessonDraft.body ?? ""} /></label>
            <label>URL do vídeo (YouTube, Vimeo ou MP4)<input name="video_url" type="url" defaultValue={lessonDraft.video_url ?? ""} /></label><label>URL da imagem<input name="image_url" type="url" defaultValue={lessonDraft.image_url ?? ""} /></label><label>URL do material complementar<input name="material_url" type="url" defaultValue={lessonDraft.material_url ?? ""} /></label>
            <label className="academy-check"><input name="required" type="checkbox" defaultChecked={lessonDraft.required ?? true} />Aula obrigatória</label><div className="academy-form-actions"><button className="academy-button" disabled={busy}>Salvar aula</button><button type="button" onClick={() => setLessonDraft(null)}>Cancelar</button>
              {lessonDraft.id ? <button type="button" onClick={() => setLessonDraft({ ...lessonDraft, id: undefined, title:`Cópia de ${lessonDraft.title}` })}>Duplicar</button> : null}
              {lessonDraft.id && lessonDraft.active ? <button type="button" className="academy-danger" onClick={() => void mutate("remove_lesson", { course_id:course.id, lesson_id:lessonDraft.id },async () => setLessonDraft(null))}>Desativar aula</button> : null}</div></form> : null}</div> : null}
        {course && tab === "assessment" ? <form key={`${course.id}-${selectedAssessment?.updated_at ?? "assessment"}`} className="academy-form" onSubmit={(event) => void saveAssessment(event)}><h3>Avaliação final</h3>
          <label className="academy-check"><input name="enabled" type="checkbox" defaultChecked={selectedAssessment?.enabled ?? false} />Exigir aprovação na prova para concluir</label>
          <div className="academy-form-row"><label>Questões por prova<input name="question_count" type="number" min={1} max={100} required defaultValue={selectedAssessment?.question_count ?? 5} /></label><label>Nota mínima (%)<input name="passing_score" type="number" min={0} max={100} step="0.01" required defaultValue={selectedAssessment?.passing_score ?? 70} /></label><label>Tentativas<input name="max_attempts" type="number" min={1} max={20} required defaultValue={selectedAssessment?.max_attempts ?? 3} /></label></div>
          <label className="academy-check"><input name="shuffle_questions" type="checkbox" defaultChecked={selectedAssessment?.shuffle_questions ?? true} />Sortear e embaralhar questões</label>
          <label className="academy-check"><input name="shuffle_options" type="checkbox" defaultChecked={selectedAssessment?.shuffle_options ?? true} />Embaralhar alternativas</label>
          <label>Revelar gabarito<select name="reveal_policy" defaultValue={selectedAssessment?.reveal_policy ?? "after_final"}><option value="after_final">Após aprovação ou fim das tentativas</option><option value="immediate">Após cada envio</option></select></label>
          <button className="academy-button" disabled={busy}>Salvar configuração</button></form> : null}
        {course && content && tab === "questions" ? <div className="academy-admin-block"><div className="academy-section-head"><h3>Banco de questões · {content.question_total}</h3><button className="academy-button academy-button-secondary" onClick={() => setQuestionDraft({ ...newQuestion,options:newQuestion.options.map((option) => ({ ...option })) })}>Nova questão</button></div>
          <div className="academy-admin-rows">{content.questions.map((item) => <article key={item.id}><div><strong>{item.body}</strong><small>{item.kind === "true_false" ? "Verdadeiro / Falso" : "Múltipla escolha"} · {item.active ? "Ativa" : "Inativa"}</small></div><button onClick={() => setQuestionDraft(fromQuestion(item))}>Editar</button></article>)}{!content.questions.length ? <p>Nenhuma questão nesta página.</p> : null}</div>
          {content.question_total > 25 ? <div className="academy-pagination"><button disabled={questionPage === 1 || busy} onClick={() => { setQuestionPage(questionPage-1); void loadContent(course.id,questionPage-1); }}>Anterior</button><span>{questionPage}</span><button disabled={questionPage*25 >= content.question_total || busy} onClick={() => { setQuestionPage(questionPage+1); void loadContent(course.id,questionPage+1); }}>Próxima</button></div> : null}
          {questionDraft ? <form className="academy-form academy-inline-form" onSubmit={(event) => void saveQuestion(event)}><h3>{questionDraft.id ? "Editar questão" : "Nova questão"}</h3>
            <label>Enunciado<textarea name="body" rows={3} required minLength={5} maxLength={2000} value={questionDraft.body} onChange={(event) => setQuestionDraft({ ...questionDraft,body:event.target.value })} /></label>
            <div className="academy-form-row"><label>Tipo<select value={questionDraft.kind} onChange={(event) => setQuestionDraft({ ...questionDraft,kind:event.target.value as QuestionDraft["kind"],options:event.target.value === "true_false" ? [{ label:"Verdadeiro",correct:true },{ label:"Falso",correct:false }] : newQuestion.options.map((option) => ({ ...option })) })}><option value="multiple_choice">Múltipla escolha</option><option value="true_false">Verdadeiro / Falso</option></select></label><label>Peso<input name="weight" type="number" min="0.01" max={100} step="0.01" defaultValue={questionDraft.weight} /></label><label>Ordem<input name="position" type="number" defaultValue={questionDraft.position} /></label></div>
            <fieldset className="academy-options"><legend>Alternativas · selecione a correta</legend>{questionDraft.options.map((option,index) => <div key={index}><input type="radio" name="correct" aria-label={`Alternativa ${index+1} correta`} checked={option.correct} onChange={() => setQuestionDraft({ ...questionDraft,options:questionDraft.options.map((entry,i) => ({ ...entry,correct:i===index })) })} />
              <input aria-label={`Texto da alternativa ${index+1}`} required maxLength={500} value={option.label} onChange={(event) => setQuestionDraft({ ...questionDraft,options:questionDraft.options.map((entry,i) => i===index ? { ...entry,label:event.target.value } : entry) })} />
              {questionDraft.kind === "multiple_choice" && questionDraft.options.length > 2 ? <button type="button" aria-label={`Remover alternativa ${index+1}`} onClick={() => { const options=questionDraft.options.filter((_,i) => i!==index); if (!options.some((entry) => entry.correct)) options[0].correct=true; setQuestionDraft({ ...questionDraft,options }); }}>×</button> : null}</div>)}
              {questionDraft.kind === "multiple_choice" && questionDraft.options.length < 8 ? <button type="button" onClick={() => setQuestionDraft({ ...questionDraft,options:[...questionDraft.options,{ label:"",correct:false }] })}>Adicionar alternativa</button> : null}</fieldset>
            <label>Explicação (opcional)<textarea name="explanation" rows={3} maxLength={2000} defaultValue={questionDraft.explanation} /></label>
            <div className="academy-form-actions"><button className="academy-button" disabled={busy}>Salvar questão</button><button type="button" onClick={() => setQuestionDraft(null)}>Cancelar</button>
              {questionDraft.id ? <button type="button" className="academy-danger" onClick={() => void mutate("remove_question",{ course_id:course.id,question_id:questionDraft.id },async () => setQuestionDraft(null))}>Desativar</button> : null}</div></form> : null}</div> : null}
        {course && tab === "results" && canViewResults ? <ResultsPanel results={results} busy={busy} search={search} courses={listing.courses} courseId={resultCourse} status={resultStatus} history={resultHistory}
          onHistory={(id) => void showResultHistory(id)}
          onCourse={async (id) => { setResultCourse(id); setResultPage(1); await loadResults(1,search,id); }}
          onStatus={async (status) => { setResultStatus(status); setResultPage(1); await loadResults(1,search,resultCourse,status); }}
          onSearch={async (value) => { setSearch(value); setResultPage(1); await loadResults(1,value,resultCourse); }}
          onPage={async (page) => { setResultPage(page); await loadResults(page); }} onGrade={(entry,kind) => { setGradeAction({ kind,result:entry }); setReason(""); setScore(entry.final_score ?? 70); }} canAdjust={canAdjust} canReopen={canReopen} /> : null}
      </section></div>
    {confirmation && course ? <HpsmDialog title={confirmation === "publish" ? "Publicar curso?" : confirmation === "archive" ? "Arquivar curso?" : "Despublicar curso?"}
      description={confirmation === "archive" ? "O histórico será preservado, mas novas aulas e provas ficarão indisponíveis para os alunos." : confirmation === "publish" ? "O curso ficará disponível para os profissionais autorizados." : "O curso ficará temporariamente indisponível para os alunos."}
      confirmLabel="Confirmar" loading={busy} onClose={() => setConfirmation(null)} onConfirm={() => void mutate(confirmation,{ course_id:course.id },async () => setConfirmation(null))} /> : null}
    {gradeAction ? <HpsmDialog title={gradeAction.kind === "grade" ? "Ajustar nota" : "Liberar tentativa adicional"} description={`Profissional: ${gradeAction.result.professional_name} · ${gradeAction.result.course_name}. A justificativa ficará registrada na auditoria.`}
      confirmLabel="Registrar" loading={busy} onClose={() => setGradeAction(null)} onConfirm={() => void actGrade()}>
      {error ? <p className="academy-message error" role="alert">{error}</p> : null}
      {gradeAction.kind === "grade" ? <label className="academy-dialog-field">Nova nota (%)<input type="number" min={0} max={100} step="0.01" value={score} onChange={(event) => setScore(Number(event.target.value))} /></label> : null}
      <label className="academy-dialog-field">Motivo (mínimo 10 caracteres)<textarea minLength={10} maxLength={1000} rows={3} value={reason} onChange={(event) => setReason(event.target.value)} /></label>
    </HpsmDialog> : null}
  </main>;
}

function ResultsPanel({ results, busy, search, courses, courseId, status, history, onHistory, onCourse, onStatus, onSearch, onPage, onGrade, canAdjust, canReopen }: {
  results: AcademyAdminResults | null; busy: boolean; search: string; courses: AcademyCourse[]; courseId: number | null; status: number | null;
  history: { id: number; data: AcademyAdminResultHistory } | null; onHistory: (id: number) => void;
  onCourse: (id: number | null) => Promise<void>; onStatus: (value: number | null) => Promise<void>; onSearch: (value: string) => Promise<void>;
  onPage: (page: number) => Promise<void>; onGrade: (entry: AcademyAdminResult,kind:"grade"|"attempt") => void;
  canAdjust: boolean; canReopen: boolean;
}) {
  const [draft, setDraft] = useState(search);
  return <div className="academy-admin-block"><div className="academy-section-head"><h3>Resultados da equipe</h3><span>{results?.total ?? 0}</span></div>
    <form className="academy-result-search" onSubmit={(event) => { event.preventDefault(); void onSearch(draft); }}><input value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="Nome, passaporte ou curso" aria-label="Buscar resultados" /><button className="academy-button academy-button-secondary" disabled={busy}>Buscar</button></form>
    <div className="academy-result-filters"><label>Curso<select value={courseId ?? ""} onChange={(event) => void onCourse(event.target.value ? Number(event.target.value) : null)}><option value="">Todos</option>{courses.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
      <label>Situação<select value={status ?? ""} onChange={(event) => void onStatus(event.target.value ? Number(event.target.value) : null)}><option value="">Todos</option><option value={1}>Em andamento</option><option value={2}>Aprovados</option><option value={3}>Não aprovados</option></select></label></div>
    <div className="academy-result-list">{results?.results.map((entry) => <article key={entry.id}><div><strong>{entry.professional_name} <small>· {entry.passport}</small></strong><span>{entry.course_name} · início {academyDate(entry.started_at)} · {entry.attempt_count} tentativa(s)</span></div>
      <div className="academy-result-state"><strong>{entry.passed ? "Aprovado" : entry.final_score !== null ? "Não aprovado" : "Em andamento"}</strong><span>{entry.final_score !== null ? `${entry.final_score}%` : "Sem nota"}{entry.adjustments ? ` · ${entry.adjustments} ajuste(s)` : ""}</span></div>
      <div className="academy-row-actions"><button onClick={() => onHistory(entry.id)}>Histórico</button>{canAdjust && entry.attempt_count > 0 ? <button onClick={() => onGrade(entry,"grade")}>Ajustar nota</button> : null}{canReopen && !entry.passed && entry.attempt_count > 0 ? <button onClick={() => onGrade(entry,"attempt")}>Nova tentativa</button> : null}</div>
      {history?.id === entry.id ? <div className="academy-result-history"><strong>Tentativas</strong>{history.data.attempts.map((attempt) => <p key={attempt.id}>#{attempt.attempt_number} · {attempt.status === "submitted" ? `${attempt.score}% · ${attempt.passed ? "aprovado" : "não aprovado"}` : "em andamento"} · {academyDate(attempt.submitted_at ?? attempt.started_at)}</p>)}
        {history.data.grade_history.map((adjustment) => <p key={`g-${adjustment.id}`}><strong>Ajuste de nota:</strong> {adjustment.previous_score ?? "—"}% → {adjustment.adjusted_score}% · {academyDate(adjustment.adjusted_at)}<br />Motivo: {adjustment.reason}</p>)}
        {history.data.extra_attempts.map((grant) => <p key={`a-${grant.id}`}><strong>Tentativa adicional:</strong> {academyDate(grant.granted_at)} · {grant.reason}</p>)}
      </div> : null}</article>)}
      {results && !results.results.length ? <p>Nenhum resultado encontrado.</p> : null}</div>
    {results && results.total > 20 ? <div className="academy-pagination"><button disabled={busy || results.page === 1} onClick={() => void onPage(results.page-1)}>Anterior</button><span>Página {results.page}</span><button disabled={busy || results.page*20 >= results.total} onClick={() => void onPage(results.page+1)}>Próxima</button></div> : null}
  </div>;
}
function fromQuestion(question: AcademyQuestion): QuestionDraft {
  return { id:question.id,body:question.body,kind:question.kind,explanation:question.explanation,weight:question.weight,position:question.position,
    options:question.options.map((option) => ({ label:option.label,correct:option.correct })) };
}
function labelStatus(status?: AcademyCourse["status"]) { return status === "published" ? "Publicado" : status === "archived" ? "Arquivado" : "Rascunho"; }
function message(error: unknown) { return error instanceof Error ? error.message : "Não foi possível concluir a ação."; }
