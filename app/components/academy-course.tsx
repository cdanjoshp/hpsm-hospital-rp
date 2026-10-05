"use client";
/* eslint-disable @next/next/no-img-element -- imagens externas do material não passam pelo otimizador local */

import Link from "next/link";
import { useState } from "react";
import type { AcademyAttempt, AcademyAttemptItem, AcademyCourseDetail, AcademyLesson } from "../lib/academy";
import { academyDate, academyGet, academyPost } from "../lib/academy-client";
import { HpsmDialog } from "./hpsm-dialog";

type AttemptView = { attempt: AcademyAttempt; items: AcademyAttemptItem[]; answers_revealed: boolean };

export function AcademyCourseView({ initial, canTakeExam }: { initial: AcademyCourseDetail; canTakeExam: boolean }) {
  const [data, setData] = useState(initial);
  const [lesson, setLesson] = useState<AcademyLesson | null>(null);
  const [attempt, setAttempt] = useState<AttemptView | null>(null);
  const [confirmSubmit, setConfirmSubmit] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const course = data.course;
  const done = new Set(data.progress.filter((entry) => entry.completed_at).map((entry) => entry.lesson_id));
  const required = data.lessons.filter((entry) => entry.required);
  const progress = required.length ? Math.round(100 * required.filter((entry) => done.has(entry.id)).length / required.length) : 100;
  const canStartExam = required.every((entry) => done.has(entry.id));
  const remaining = (data.assessment?.max_attempts ?? 0) + (data.enrollment?.extra_attempts ?? 0) - data.attempts.length;
  const openAttempt = data.attempts.find((entry) => entry.status === "in_progress");
  async function refresh() { setData(await academyGet<AcademyCourseDetail>("course", { courseId: course.id })); }
  async function act<T>(action: string, payload: Record<string, unknown>, after?: (value: T) => Promise<void>) {
    setBusy(true); setError(""); setNotice("");
    try { const value = await academyPost<T>(action, { course_id: course.id, ...payload }); await after?.(value); await refresh(); return value; }
    catch (cause) { setError(cause instanceof Error ? cause.message : "Não foi possível concluir a ação."); return null; }
    finally { setBusy(false); }
  }
  async function openLesson(id: number) {
    setBusy(true); setError(""); setAttempt(null);
    try {
      const result = await academyGet<{ lesson: AcademyLesson }>("lesson", { courseId: course.id, refId: id });
      setLesson(result.lesson);
      if (course.status === "published" && !data.progress.some((entry) => entry.lesson_id === id))
        await academyPost("lesson_start", { course_id: course.id, lesson_id: id });
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Não foi possível abrir a aula."); }
    finally { setBusy(false); }
  }
  async function showAttempt(id: number) {
    setBusy(true); setError(""); setLesson(null);
    try { setAttempt(await academyGet<AttemptView>("attempt", { courseId: course.id, refId: id })); }
    catch (cause) { setError(cause instanceof Error ? cause.message : "Não foi possível abrir a avaliação."); }
    finally { setBusy(false); }
  }
  async function choose(itemId: number, optionId: number) {
    setBusy(true); setError("");
    try {
      await academyPost("attempt_save", { course_id: course.id, attempt_id: attempt?.attempt.id, item_id: itemId, option_id: optionId });
      setAttempt((current) => current ? { ...current, items: current.items.map((entry) => entry.id === itemId ? { ...entry, selected_option_id: optionId } : entry) } : null);
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Não foi possível salvar a resposta."); }
    finally { setBusy(false); }
  }
  return <main className="academy-page academy-course-page">
    <nav className="academy-breadcrumb"><Link href="/academia" prefetch={false}>Academia HPSM</Link><span>/</span><span>{course.name}</span></nav>
    <header className="academy-course-header"><div><span className="academy-eyebrow">{course.category}</span><h1>{course.name}</h1>
      <p>{course.description || course.short_description}</p><div className="academy-chips"><span>{data.lessons.length} aulas</span>
        {data.assessment?.enabled ? <><span>Nota mínima {data.assessment.passing_score}%</span><span>{data.assessment.max_attempts} tentativas</span></> : <span>Sem prova</span>}</div></div>
      <div className="academy-overview-progress"><strong>{progress}%</strong><span>Aulas concluídas</span><div className="academy-progress"><span style={{ width: `${progress}%` }} /></div></div></header>
    {error ? <div className="academy-message error" role="alert">{error}</div> : null}{notice ? <div className="academy-message" role="status">{notice}</div> : null}
    {!data.enrollment ? <div className="academy-start"><p>Inicie para acompanhar o progresso das aulas e liberar a avaliação.</p>
      <button className="academy-button" disabled={busy || course.status !== "published"} onClick={() => void act("enroll", {}, async () => { setNotice("Curso iniciado."); })}>Iniciar curso</button></div> : null}
    {data.enrollment ? <div className="academy-study-layout"><aside className="academy-lesson-list"><div className="academy-section-head"><h2>Aulas</h2><span>{done.size}/{required.length}</span></div>
      {data.lessons.map((item, index) => <button type="button" key={item.id} className={lesson?.id === item.id ? "current" : ""} disabled={busy}
        onClick={() => void openLesson(item.id)}><span className="academy-lesson-number">{String(index + 1).padStart(2,"0")}</span><span><strong>{item.title}</strong><small>{done.has(item.id) ? "Concluída" : "Pendente"}</small></span><span aria-hidden="true">{done.has(item.id) ? "✓" : ""}</span></button>)}
      {data.assessment?.enabled && canTakeExam ? <div className="academy-assessment-nav"><strong>Avaliação final</strong><span>{canStartExam ? "Disponível" : "Conclua as aulas obrigatórias"}</span></div> : null}
    </aside><section className="academy-study-main">
      {lesson ? <article className="academy-lesson"><span className="academy-eyebrow">AULA {data.lessons.findIndex((entry) => entry.id === lesson.id) + 1}</span><h2>{lesson.title}</h2>
        {lesson.description ? <p className="academy-lesson-description">{lesson.description}</p> : null}
        <LessonText body={lesson.body ?? ""} />
        {lesson.video_url ? <AcademyVideo url={lesson.video_url} title={lesson.title} /> : null}
        {lesson.image_url ? <img className="academy-lesson-image" src={lesson.image_url} alt={`Ilustração da aula ${lesson.title}`} loading="lazy" /> : null}
        {lesson.material_url ? <a className="academy-material" href={lesson.material_url} target="_blank" rel="noopener noreferrer">Abrir material complementar</a> : null}
        <div className="academy-lesson-footer">{done.has(lesson.id) ? <span>Aula concluída em {academyDate(data.progress.find((entry) => entry.lesson_id === lesson.id)?.completed_at)}</span>
          : course.status === "published" ? <button className="academy-button" disabled={busy} onClick={() => void act("lesson_complete", { lesson_id: lesson.id }, async () => { setNotice("Aula concluída."); })}>Concluir aula</button> : null}</div>
      </article> : attempt ? <div className="academy-exam"><div className="academy-section-head"><h2>Avaliação · tentativa {attempt.attempt.attempt_number}</h2><span>{attempt.attempt.status === "submitted" ? `${attempt.attempt.score}%` : `${attempt.items.filter((item) => item.selected_option_id).length}/${attempt.items.length} respondidas`}</span></div>
        {attempt.attempt.status === "submitted" ? <div className={`academy-result ${attempt.attempt.passed ? "passed" : "failed"}`}><strong>{attempt.attempt.passed ? "Aprovado" : "Não aprovado"}</strong><span>Nota {attempt.attempt.score}% · mínimo {attempt.attempt.passing_score_snapshot}%</span></div> : null}
        {attempt.items.map((item) => <fieldset className="academy-question" key={item.id} disabled={busy || attempt.attempt.status === "submitted"}><legend><span>{String(item.position).padStart(2,"0")}</span>{item.body}</legend>
          {item.options.map((option) => <label key={option.id} className={item.selected_option_id === option.id ? "chosen" : ""}><input type="radio" name={`question-${item.id}`} checked={item.selected_option_id === option.id} onChange={() => void choose(item.id,option.id)} />{option.label}
            {attempt.answers_revealed && option.id === item.correct_option_id ? <em>Correta</em> : null}</label>)}
          {attempt.answers_revealed && item.explanation ? <p className="academy-explanation">{item.explanation}</p> : null}
        </fieldset>)}
        {attempt.attempt.status === "in_progress" ? <button className="academy-button" disabled={busy} onClick={() => setConfirmSubmit(true)}>Finalizar avaliação</button> : null}
      </div> : <div className="academy-study-welcome"><h2>{data.enrollment.passed ? "Curso concluído" : "Continue de onde parou"}</h2>
        <p>{data.enrollment.passed ? `Conclusão em ${academyDate(data.enrollment.completed_at)}${data.enrollment.final_score !== null ? ` · nota ${data.enrollment.final_score}%` : ""}.` : "Escolha uma aula para estudar. Seu progresso fica salvo."}</p>
        {!data.enrollment.passed && data.lessons.some((item) => !done.has(item.id)) ? <button className="academy-button" disabled={busy} onClick={() => void openLesson(data.lessons.find((item) => !done.has(item.id))!.id)}>Continuar curso</button> : null}</div>}
      {data.assessment?.enabled && canTakeExam ? <div className="academy-attempts"><h3>Avaliação final</h3><p>As respostas são salvas durante a prova. A nota é calculada após o envio.</p>
        {data.attempts.map((item) => <button key={item.id} type="button" disabled={busy} onClick={() => void showAttempt(item.id)}><strong>Tentativa {item.attempt_number}</strong><span>{item.status === "in_progress" ? "Em andamento" : `${item.score}% · ${item.passed ? "Aprovado" : "Não aprovado"}`}</span></button>)}
        {canStartExam && !data.enrollment.passed && !openAttempt && remaining > 0 && course.status === "published" ? <button className="academy-button" disabled={busy} onClick={() => void act<{ attempt_id: number }>("attempt_start", {}, async (result) => { await showAttempt(result.attempt_id); })}>Iniciar avaliação · {remaining} {remaining === 1 ? "tentativa" : "tentativas"} disponível(is)</button> : null}
        {!canStartExam ? <small>Conclua todas as aulas obrigatórias para liberar a prova.</small> : null}
        {canStartExam && remaining <= 0 && !data.enrollment.passed ? <small>Tentativas encerradas. A Diretoria pode liberar outra, se necessário.</small> : null}
      </div> : null}
    </section></div> : null}
    {confirmSubmit ? <HpsmDialog title="Finalizar avaliação?" description="As respostas serão enviadas para correção. Esta tentativa não poderá ser alterada depois." confirmLabel="Finalizar avaliação" loading={busy} onClose={() => setConfirmSubmit(false)} onConfirm={() => void act("attempt_submit", { attempt_id: attempt?.attempt.id }, async () => { setConfirmSubmit(false); if (attempt) await showAttempt(attempt.attempt.id); })} /> : null}
  </main>;
}

function AcademyVideo({ url, title }: { url: string; title: string }) {
  let embed: string | null = null;
  let directVideo = false;
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:") return null;
    if (["youtube.com","www.youtube.com","m.youtube.com","youtu.be"].includes(parsed.hostname)) {
      const id = parsed.hostname === "youtu.be" ? parsed.pathname.slice(1) : parsed.searchParams.get("v") ?? parsed.pathname.replace(/^\/embed\//, "");
      if (/^[a-zA-Z0-9_-]{11}$/.test(id)) embed = `https://www.youtube-nocookie.com/embed/${id}`;
    } else if (["vimeo.com","www.vimeo.com","player.vimeo.com"].includes(parsed.hostname)) {
      const id = parsed.pathname.split("/").filter(Boolean).at(-1);
      if (id && /^\d+$/.test(id)) embed = `https://player.vimeo.com/video/${id}`;
    }
    directVideo = /\.mp4($|\?)/i.test(parsed.pathname + parsed.search);
  } catch { /* URL malformada: não incorpora. */ }
  if (embed) return <div className="academy-video"><iframe src={embed} title={`Vídeo: ${title}`} allow="fullscreen; picture-in-picture" allowFullScreen loading="lazy" referrerPolicy="strict-origin-when-cross-origin" /></div>;
  if (directVideo) return <video className="academy-direct-video" controls preload="metadata" src={url}>Seu navegador não suporta este vídeo.</video>;
  return <a className="academy-material" href={url} target="_blank" rel="noopener noreferrer">Abrir vídeo da aula</a>;
}

function LessonText({ body }: { body: string }) {
  if (!body.trim()) return null;
  return <div className="academy-lesson-text">{body.split(/\n/).map((line, index) => {
    const trimmed = line.trim();
    if (!trimmed) return <div className="academy-text-gap" key={index} />;
    if (trimmed.startsWith("### ")) return <h4 key={index}>{inline(trimmed.slice(4))}</h4>;
    if (trimmed.startsWith("## ")) return <h3 key={index}>{inline(trimmed.slice(3))}</h3>;
    if (trimmed.startsWith("# ")) return <h2 key={index}>{inline(trimmed.slice(2))}</h2>;
    if (/^[-*] /.test(trimmed)) return <p className="academy-bullet" key={index}>• {inline(trimmed.slice(2))}</p>;
    return <p key={index}>{inline(trimmed)}</p>;
  })}</div>;
}
function inline(value: string) {
  return value.split(/(\*\*[^*]+\*\*|\[[^\]]+\]\(https:\/\/[^)]+\))/g).map((part,index) => {
    if (part.startsWith("**") && part.endsWith("**")) return <strong key={index}>{part.slice(2,-2)}</strong>;
    const match = part.match(/^\[([^\]]+)\]\((https:\/\/[^)]+)\)$/);
    if (match) return <a href={match[2]} key={index} target="_blank" rel="noopener noreferrer">{match[1]}</a>;
    return part;
  });
}
