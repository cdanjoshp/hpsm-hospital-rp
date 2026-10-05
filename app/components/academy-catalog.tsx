"use client";
/* eslint-disable @next/next/no-img-element -- capas HTTPS informadas pela Diretoria podem vir de qualquer provider */

import Link from "next/link";
import { useState } from "react";
import type { AcademyCatalog, AcademyCourse } from "../lib/academy";

export function AcademyCatalogView({ initial, canManage }: { initial: AcademyCatalog; canManage: boolean }) {
  const [filter, setFilter] = useState("Todos");
  const courses = initial.courses.filter((course) => filter === "Todos" || course.category === filter);
  const categories = ["Todos", ...new Set(initial.courses.map((course) => course.category))];
  const continuing = courses.filter((course) => course.started_at && !course.passed);
  const completed = courses.filter((course) => course.passed);
  const available = courses.filter((course) => !course.started_at);
  return <main className="academy-page">
    <header className="academy-heading"><div><span className="academy-eyebrow">FORMAÇÃO PROFISSIONAL</span><h2>Seus cursos</h2>
      <p>Continue as aulas ou escolha um novo curso.</p></div>{canManage ? <Link className="academy-button academy-button-secondary" href="/academia/gestao" prefetch={false}>Gestão da Academia</Link> : null}</header>
    {initial.courses.length ? <nav className="academy-filters" aria-label="Categorias">{categories.map((category) =>
      <button key={category} type="button" className={filter === category ? "selected" : ""} onClick={() => setFilter(category)}>{category}</button>)}</nav> : null}
    <CourseSection title="Continuar estudando" courses={continuing} />
    <CourseSection title="Cursos disponíveis" courses={available} />
    <CourseSection title="Concluídos" courses={completed} />
    {!courses.length ? <div className="academy-empty"><strong>Nenhum curso por aqui ainda.</strong><p>{filter === "Todos" ? "Os cursos publicados pela Diretoria aparecerão nesta página." : "Experimente outra categoria."}</p></div> : null}
  </main>;
}

function CourseSection({ title, courses }: { title: string; courses: AcademyCourse[] }) {
  if (!courses.length) return null;
  return <section className="academy-section"><div className="academy-section-head"><h2>{title}</h2><span>{courses.length}</span></div><div className="academy-grid">{courses.map((course) => {
    const progress = course.lesson_count ? Math.round(100 * (course.completed_lessons ?? 0) / course.lesson_count) : 0;
    return <Link className="academy-card" href={`/academia/${course.id}`} prefetch={false} key={course.id}>
      {course.cover_url ? <div className="academy-card-cover"><img src={course.cover_url} alt="" loading="lazy" /></div> : <div className="academy-card-cover academy-card-cover-plain" aria-hidden="true"><span>HPSM</span></div>}
      <div className="academy-card-content"><span className="academy-category">{course.category}</span><h3>{course.name}</h3>
        <p>{course.short_description || "Curso da Academia HPSM"}</p><div className="academy-card-meta">{course.required ? <span>Obrigatório</span> : null}</div>
        {course.started_at ? <><div className="academy-progress" role="progressbar" aria-valuenow={progress} aria-valuemin={0} aria-valuemax={100} aria-label="Aulas concluídas"><span style={{ width: `${progress}%` }} /></div>
          <small>{course.passed ? `Concluído · ${course.final_score !== null && course.final_score !== undefined ? `${course.final_score}%` : "sem prova"}` : course.status === "archived" ? "Arquivado · histórico disponível" : `${progress}% das aulas · ${course.final_score !== null && course.final_score !== undefined ? `não aprovado, última nota ${course.final_score}%` : "em andamento"}`}</small></> : null}
        <strong className="academy-card-action">{course.passed || course.status === "archived" ? "Ver histórico" : course.started_at ? "Continuar curso" : "Abrir curso"}</strong>
      </div></Link>;
  })}</div></section>;
}
