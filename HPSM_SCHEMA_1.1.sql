-- HPSM 1.1.0 — snapshot estrutural de referência
-- Consolidado em 2026-09-16 (UTC) a partir do snapshot 1.0.0 e do delta estrutural pós-freeze confirmado no projeto Supabase canônico.
-- Contém somente DDL e metadados estruturais; nenhum registro operacional foi exportado.
-- NÃO É migration incremental. Para recuperação, use a tag v1.1.0 e aplique supabase/migrations em ordem.
-- Funções, policies, triggers e grants são preservados abaixo para comparação técnica.

create schema if not exists private;

-- Extensões instaladas (inventário; versões podem ser geridas pelo Supabase).
-- EXTENSION pg_stat_statements 1.11
-- EXTENSION pg_trgm 1.6
-- EXTENSION pgcrypto 1.3
-- EXTENSION supabase_vault 0.3.1
-- EXTENSION uuid-ossp 1.1

-- Tipos enumerados.

-- Sequências observadas (as colunas identity continuam declaradas nas tabelas).
-- SEQUENCE "public"."attendance_items_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."attendances_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."clinical_casts_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."clinical_exam_report_versions_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."clinical_exam_status_history_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."clinical_exams_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."courses_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."exam_categories_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."exam_types_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."notifications_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."partnership_pending_beneficiaries_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."partnership_responsible_history_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."partnership_status_history_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."partnerships_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."patient_health_plan_requests_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."patient_partnerships_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."patient_portal_login_attempts_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."patients_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."recruitment_decisions_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."rh_absence_requests_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."rh_disciplinary_reviews_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."rh_hour_justifications_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."rh_hour_snapshots_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."rh_leave_week_adjustments_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."rh_warnings_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."rh_week_closures_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."rh_week_reopen_events_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."rh_weekly_records_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."service_catalog_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."staff_course_records_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."staff_position_history_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."staff_position_transition_rules_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."staff_positions_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."staff_promotion_reviews_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1
-- SEQUENCE "public"."user_permission_grants_id_seq" type=bigint start=1 min=1 max=9223372036854776000 increment=1 cycle=false cache=1

-- Tabelas públicas (sem dados).
create table "public"."profiles" (
  "id" uuid default gen_random_uuid() not null,
  "user_id" uuid not null,
  "passport" text not null,
  "display_name" text not null,
  "role_code" text default 'funcionario'::text not null,
  "status" text default 'active'::text not null,
  "must_change_password" boolean default true not null,
  "password_reset_by" uuid,
  "created_by" uuid,
  "updated_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "position_id" bigint
);
alter table "public"."profiles" enable row level security;
alter table "public"."profiles" force row level security;

create table "public"."audit_logs" (
  "id" uuid default gen_random_uuid() not null,
  "actor_user_id" uuid,
  "actor_passport" text,
  "action" text not null,
  "entity_name" text not null,
  "entity_id" text,
  "old_values" jsonb,
  "new_values" jsonb,
  "created_at" timestamp with time zone default now() not null
);
alter table "public"."audit_logs" enable row level security;
alter table "public"."audit_logs" force row level security;

create table "public"."system_settings" (
  "key" text not null,
  "value" jsonb default '{}'::jsonb not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."system_settings" enable row level security;
alter table "public"."system_settings" force row level security;

create table "public"."service_catalog" (
  "id" bigint generated by default as identity not null,
  "name" text not null,
  "category" text default 'Geral'::text not null,
  "unit_price" numeric not null,
  "active" boolean default true not null,
  "sort_order" integer default 0 not null,
  "created_by" uuid,
  "updated_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "code" text not null,
  "icon" text not null,
  "image_path" text
);
alter table "public"."service_catalog" enable row level security;
alter table "public"."service_catalog" force row level security;

create table "public"."attendances" (
  "id" bigint generated by default as identity not null,
  "patient_name" text not null,
  "patient_passport" text not null,
  "status" text default 'completed'::text not null,
  "subtotal" numeric not null,
  "discount" numeric default 0 not null,
  "total" numeric generated always as ((subtotal - discount)) stored,
  "notes" text,
  "performed_by" uuid not null,
  "cancelled_by" uuid,
  "cancelled_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "patient_id" bigint,
  "plan_code" text,
  "plan_name" text,
  "partnership_id" bigint,
  "partnership_name" text
);
alter table "public"."attendances" enable row level security;
alter table "public"."attendances" force row level security;

create table "public"."attendance_items" (
  "id" bigint generated by default as identity not null,
  "attendance_id" bigint not null,
  "service_id" bigint not null,
  "service_name" text not null,
  "unit_price" numeric not null,
  "quantity" smallint not null,
  "created_at" timestamp with time zone default now() not null,
  "discount_percent" numeric default 0 not null,
  "discount_amount" numeric generated always as (round((((unit_price * (quantity)::numeric) * discount_percent) / (100)::numeric), 2)) stored,
  "line_total" numeric generated always as (((unit_price * (quantity)::numeric) - round((((unit_price * (quantity)::numeric) * discount_percent) / (100)::numeric), 2))) stored
);
alter table "public"."attendance_items" enable row level security;
alter table "public"."attendance_items" force row level security;

create table "public"."patients" (
  "id" bigint generated by default as identity not null,
  "passport" text not null,
  "name" text not null,
  "phone" text not null,
  "created_by" uuid,
  "updated_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "emergency_contact_name" text,
  "emergency_contact_phone" text,
  "plan_code" text,
  "birth_date" date
);
alter table "public"."patients" enable row level security;
alter table "public"."patients" force row level security;

create table "public"."benefit_plans" (
  "code" text not null,
  "name" text not null,
  "sort_order" smallint not null
);
alter table "public"."benefit_plans" enable row level security;
alter table "public"."benefit_plans" force row level security;

create table "public"."plan_discounts" (
  "plan_code" text not null,
  "service_id" bigint not null,
  "discount_percent" numeric default 0 not null,
  "updated_by" uuid,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."plan_discounts" enable row level security;
alter table "public"."plan_discounts" force row level security;

create table "public"."recruitment_applications" (
  "id" uuid default gen_random_uuid() not null,
  "full_name" text not null,
  "passport" text not null,
  "birth_day" smallint not null,
  "birth_month" smallint not null,
  "city_phone" text not null,
  "discord_id" text not null,
  "availability" text[] not null,
  "prior_experience" boolean not null,
  "experience_summary" text,
  "interest_area" text not null,
  "motivation" text not null,
  "external_calls" text not null,
  "status" text default 'submitted'::text not null,
  "review_notes" text,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."recruitment_applications" enable row level security;
alter table "public"."recruitment_applications" force row level security;

create table "public"."recruitment_decisions" (
  "id" bigint generated by default as identity not null,
  "application_id" uuid not null,
  "decision" text not null,
  "reason" text,
  "decided_by" uuid not null,
  "decided_at" timestamp with time zone default now() not null
);
alter table "public"."recruitment_decisions" enable row level security;
alter table "public"."recruitment_decisions" force row level security;

create table "public"."rh_hour_snapshots" (
  "id" bigint generated by default as identity not null,
  "employee_id" uuid not null,
  "reference_month" date not null,
  "reading_date" date not null,
  "total_minutes" integer not null,
  "note" text,
  "created_by" uuid not null,
  "updated_by" uuid not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."rh_hour_snapshots" enable row level security;
alter table "public"."rh_hour_snapshots" force row level security;

create table "public"."rh_absence_requests" (
  "id" bigint generated by default as identity not null,
  "employee_id" uuid not null,
  "start_date" date not null,
  "end_date" date not null,
  "reason" text not null,
  "status" text default 'pending'::text not null,
  "approval_effect" text,
  "review_note" text,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone,
  "cancelled_by" uuid,
  "cancelled_at" timestamp with time zone,
  "requested_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "observation" text
);
alter table "public"."rh_absence_requests" enable row level security;
alter table "public"."rh_absence_requests" force row level security;

create table "public"."rh_weekly_records" (
  "id" bigint generated by default as identity not null,
  "employee_id" uuid not null,
  "week_start" date not null,
  "week_end" date not null,
  "cycle_month" date not null,
  "required_minutes" integer default 600 not null,
  "worked_minutes" integer not null,
  "status" text not null,
  "absence_request_id" bigint,
  "calculation_details" jsonb default '{}'::jsonb not null,
  "closure_note" text,
  "closed_by" uuid,
  "closed_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone default now() not null,
  "closure_id" bigint not null,
  "base_required_minutes" integer default 600 not null,
  "leave_deduction_minutes" integer default 0 not null,
  "deficit_minutes" integer default 0 not null,
  "justification_minutes" integer default 0 not null,
  "remaining_deficit_minutes" integer default 0 not null,
  "closure_status" text default 'closed'::text not null
);
alter table "public"."rh_weekly_records" enable row level security;
alter table "public"."rh_weekly_records" force row level security;

create table "public"."rh_warnings" (
  "id" bigint generated by default as identity not null,
  "employee_id" uuid not null,
  "weekly_record_id" bigint,
  "cycle_month" date not null,
  "sequence_in_cycle" smallint not null,
  "reason" text not null,
  "status" text default 'active'::text not null,
  "issued_by" uuid not null,
  "issued_at" timestamp with time zone default now() not null,
  "annulled_by" uuid,
  "annulled_at" timestamp with time zone,
  "annulment_reason" text,
  "updated_at" timestamp with time zone default now() not null,
  "origin" text default 'weekly_closure'::text not null,
  "category" text default 'weekly_goal'::text not null,
  "impacts_progression" boolean default false not null,
  "progression_flagged_by" uuid,
  "progression_flagged_at" timestamp with time zone,
  "progression_impact_note" text
);
alter table "public"."rh_warnings" enable row level security;
alter table "public"."rh_warnings" force row level security;

create table "public"."rh_disciplinary_reviews" (
  "id" bigint generated by default as identity not null,
  "employee_id" uuid not null,
  "cycle_month" date not null,
  "triggered_by_warning_id" bigint not null,
  "status" text default 'pending'::text not null,
  "triggered_by" uuid not null,
  "triggered_at" timestamp with time zone default now() not null,
  "decided_by" uuid,
  "decided_at" timestamp with time zone,
  "decision_note" text,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."rh_disciplinary_reviews" enable row level security;
alter table "public"."rh_disciplinary_reviews" force row level security;

create table "public"."notifications" (
  "id" bigint generated by default as identity not null,
  "kind" text not null,
  "recipient_id" uuid,
  "audience" text,
  "priority" text default 'normal'::text not null,
  "title" text not null,
  "body" text not null,
  "action_url" text,
  "created_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "expires_at" timestamp with time zone,
  "archived_at" timestamp with time zone,
  "archived_by" uuid,
  "source_type" text,
  "source_id" text,
  "required_permission" text,
  "resolved_at" timestamp with time zone,
  "resolved_by" uuid
);
alter table "public"."notifications" enable row level security;
alter table "public"."notifications" force row level security;

create table "public"."notification_reads" (
  "notification_id" bigint not null,
  "user_id" uuid not null,
  "read_at" timestamp with time zone default now() not null
);
alter table "public"."notification_reads" enable row level security;
alter table "public"."notification_reads" force row level security;

create table "public"."rh_leave_week_adjustments" (
  "id" bigint generated by default as identity not null,
  "leave_request_id" bigint not null,
  "employee_id" uuid not null,
  "week_start" date not null,
  "deducted_minutes" integer not null,
  "approved_by" uuid not null,
  "approved_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."rh_leave_week_adjustments" enable row level security;
alter table "public"."rh_leave_week_adjustments" force row level security;

create table "public"."rh_week_closures" (
  "id" bigint generated by default as identity not null,
  "week_start" date not null,
  "week_end" date not null,
  "status" text default 'open'::text not null,
  "started_by" uuid not null,
  "started_at" timestamp with time zone default now() not null,
  "closed_by" uuid,
  "closed_at" timestamp with time zone,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."rh_week_closures" enable row level security;
alter table "public"."rh_week_closures" force row level security;

create table "public"."rh_week_reopen_events" (
  "id" bigint generated by default as identity not null,
  "closure_id" bigint not null,
  "reason" text not null,
  "reopened_by" uuid not null,
  "reopened_at" timestamp with time zone default now() not null
);
alter table "public"."rh_week_reopen_events" enable row level security;
alter table "public"."rh_week_reopen_events" force row level security;

create table "public"."rh_hour_justifications" (
  "id" bigint generated by default as identity not null,
  "weekly_record_id" bigint not null,
  "employee_id" uuid not null,
  "deficit_minutes" integer not null,
  "reason" text not null,
  "status" text default 'pending'::text not null,
  "credited_minutes" integer,
  "review_note" text,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone,
  "submitted_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."rh_hour_justifications" enable row level security;
alter table "public"."rh_hour_justifications" force row level security;

create table "public"."staff_positions" (
  "id" bigint generated by default as identity not null,
  "code" text not null,
  "name" text not null,
  "active" boolean default true not null,
  "sort_order" integer default 0 not null,
  "created_by" uuid not null,
  "updated_by" uuid not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "level" smallint not null,
  "advancement_mode" text not null,
  "official" boolean default false not null
);
alter table "public"."staff_positions" enable row level security;
alter table "public"."staff_positions" force row level security;

create table "public"."system_permissions" (
  "code" text not null,
  "module" text not null,
  "label" text not null,
  "description" text not null,
  "sort_order" integer default 0 not null
);
alter table "public"."system_permissions" enable row level security;
alter table "public"."system_permissions" force row level security;

create table "public"."staff_position_permissions" (
  "position_id" bigint not null,
  "permission_code" text not null,
  "granted_by" uuid not null,
  "granted_at" timestamp with time zone default now() not null
);
alter table "public"."staff_position_permissions" enable row level security;
alter table "public"."staff_position_permissions" force row level security;

create table "public"."user_permission_grants" (
  "id" bigint generated by default as identity not null,
  "user_id" uuid not null,
  "permission_code" text not null,
  "valid_from" timestamp with time zone default now() not null,
  "expires_at" timestamp with time zone,
  "reason" text,
  "granted_by" uuid not null,
  "granted_at" timestamp with time zone default now() not null,
  "revoked_at" timestamp with time zone,
  "revoked_by" uuid,
  "revoked_reason" text,
  "grant_kind" text default 'temporary'::text not null
);
alter table "public"."user_permission_grants" enable row level security;
alter table "public"."user_permission_grants" force row level security;

create table "public"."staff_position_history" (
  "id" bigint generated by default as identity not null,
  "employee_id" uuid not null,
  "from_position_id" bigint,
  "to_position_id" bigint not null,
  "event_type" text not null,
  "decided_by" uuid not null,
  "effective_at" timestamp with time zone default now() not null,
  "note" text,
  "created_at" timestamp with time zone default now() not null
);
alter table "public"."staff_position_history" enable row level security;
alter table "public"."staff_position_history" force row level security;

create table "public"."staff_position_transition_rules" (
  "id" bigint generated by default as identity not null,
  "from_position_id" bigint not null,
  "to_position_id" bigint not null,
  "transition_type" text not null,
  "min_days" smallint default 15 not null,
  "min_worked_minutes" integer default 1800 not null,
  "min_attendances" smallint default 3 not null,
  "active" boolean default true not null,
  "updated_by" uuid not null,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."staff_position_transition_rules" enable row level security;
alter table "public"."staff_position_transition_rules" force row level security;

create table "public"."staff_promotion_reviews" (
  "id" bigint generated by default as identity not null,
  "employee_id" uuid not null,
  "from_position_id" bigint not null,
  "to_position_id" bigint not null,
  "status" text default 'pending'::text not null,
  "required_days" smallint not null,
  "elapsed_days" integer not null,
  "worked_minutes" integer not null,
  "attendance_count" integer not null,
  "flagged_warning_count" integer not null,
  "created_at" timestamp with time zone default now() not null,
  "decided_by" uuid,
  "decided_at" timestamp with time zone,
  "decision_note" text,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."staff_promotion_reviews" enable row level security;
alter table "public"."staff_promotion_reviews" force row level security;

create table "public"."courses" (
  "id" bigint generated by default as identity not null,
  "name" text not null,
  "description" text default ''::text not null,
  "active" boolean default true not null,
  "created_by" uuid not null,
  "updated_by" uuid not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."courses" enable row level security;
alter table "public"."courses" force row level security;

create table "public"."staff_course_records" (
  "id" bigint generated by default as identity not null,
  "course_id" bigint not null,
  "employee_id" uuid not null,
  "status" text default 'pending'::text not null,
  "assigned_by" uuid not null,
  "assigned_at" timestamp with time zone default now() not null,
  "completed_by" uuid,
  "completed_at" timestamp with time zone,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."staff_course_records" enable row level security;
alter table "public"."staff_course_records" force row level security;

create table "public"."patient_health_plan_requests" (
  "id" bigint generated by default as identity not null,
  "patient_id" bigint not null,
  "attendance_id" bigint not null,
  "status" text default 'pending'::text not null,
  "requested_at" timestamp with time zone default now() not null,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone,
  "rejection_reason" text,
  "coverage_start" timestamp with time zone,
  "coverage_end" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."patient_health_plan_requests" enable row level security;
alter table "public"."patient_health_plan_requests" force row level security;

create table "public"."exam_categories" (
  "id" bigint generated by default as identity not null,
  "code" text not null,
  "name" text not null,
  "active" boolean default true not null,
  "sort_order" integer default 0 not null,
  "created_by" uuid,
  "updated_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."exam_categories" enable row level security;
alter table "public"."exam_categories" force row level security;

create table "public"."exam_types" (
  "id" bigint generated by default as identity not null,
  "category_id" bigint not null,
  "code" text not null,
  "name" text not null,
  "description" text,
  "active" boolean default true not null,
  "sort_order" integer default 0 not null,
  "result_config" jsonb default '{}'::jsonb not null,
  "created_by" uuid,
  "updated_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."exam_types" enable row level security;
alter table "public"."exam_types" force row level security;

create table "public"."clinical_exams" (
  "id" bigint generated by default as identity not null,
  "patient_id" bigint not null,
  "exam_type_id" bigint not null,
  "attendance_id" bigint,
  "status" text default 'requested'::text not null,
  "requested_by" uuid not null,
  "responsible_professional_id" uuid not null,
  "indication" text not null,
  "clinical_context" text,
  "technique" text,
  "findings" text,
  "conclusion" text,
  "result_data" jsonb default '{}'::jsonb not null,
  "correction_reason" text,
  "requested_at" timestamp with time zone default now() not null,
  "started_at" timestamp with time zone,
  "submitted_for_review_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "reviewed_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "final_report_snapshot" jsonb
);
alter table "public"."clinical_exams" enable row level security;
alter table "public"."clinical_exams" force row level security;

create table "public"."clinical_exam_status_history" (
  "id" bigint generated by default as identity not null,
  "exam_id" bigint not null,
  "from_status" text,
  "to_status" text not null,
  "changed_by" uuid not null,
  "note" text,
  "changed_at" timestamp with time zone default now() not null
);
alter table "public"."clinical_exam_status_history" enable row level security;
alter table "public"."clinical_exam_status_history" force row level security;

create table "public"."clinical_exam_images" (
  "id" uuid not null,
  "exam_id" bigint not null,
  "storage_path" text not null,
  "original_filename" text not null,
  "mime_type" text not null,
  "file_size" bigint not null,
  "sort_order" integer default 0 not null,
  "caption" text,
  "source" text default 'upload'::text not null,
  "uploaded_by" uuid not null,
  "removed_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "removed_at" timestamp with time zone
);
alter table "public"."clinical_exam_images" enable row level security;
alter table "public"."clinical_exam_images" force row level security;

create table "public"."clinical_exam_report_versions" (
  "id" bigint generated by default as identity not null,
  "exam_id" bigint not null,
  "version_number" integer not null,
  "snapshot" jsonb not null,
  "submitted_by" uuid not null,
  "submitted_at" timestamp with time zone default now() not null,
  "decision" text default 'pending'::text not null,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone,
  "review_reason" text
);
alter table "public"."clinical_exam_report_versions" enable row level security;
alter table "public"."clinical_exam_report_versions" force row level security;

create table "public"."exam_ai_generations" (
  "id" uuid default gen_random_uuid() not null,
  "exam_id" bigint not null,
  "generation_type" text not null,
  "status" text default 'requested'::text not null,
  "requested_by" uuid not null,
  "model" text not null,
  "reasoning_effort" text not null,
  "prompt_version" text not null,
  "source_exam_updated_at" timestamp with time zone not null,
  "openai_response_id" text,
  "input_tokens" integer,
  "output_tokens" integer,
  "total_tokens" integer,
  "suggestion_payload" jsonb,
  "error_code" text,
  "idempotency_key" uuid not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "completed_at" timestamp with time zone,
  "failed_at" timestamp with time zone,
  "applied_at" timestamp with time zone,
  "discarded_at" timestamp with time zone,
  "image_quality" text,
  "image_size" text,
  "image_count" integer,
  "draft_storage_path" text,
  "draft_mime_type" text,
  "draft_file_size" bigint,
  "official_image_id" uuid,
  "source_image_generation_id" uuid,
  "source_image_id" uuid
);
alter table "public"."exam_ai_generations" enable row level security;
alter table "public"."exam_ai_generations" force row level security;

create table "public"."clinical_exam_documents" (
  "id" uuid not null,
  "exam_id" bigint not null,
  "storage_path" text not null,
  "mime_type" text default 'image/png'::text not null,
  "file_size" bigint not null,
  "pixel_width" integer not null,
  "pixel_height" integer not null,
  "render_version" text not null,
  "created_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "created_by_patient_id" bigint
);
alter table "public"."clinical_exam_documents" enable row level security;
alter table "public"."clinical_exam_documents" force row level security;

create table "public"."clinical_exam_document_shares" (
  "id" uuid default gen_random_uuid() not null,
  "exam_id" bigint not null,
  "document_id" uuid not null,
  "created_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "revoked_by" uuid,
  "revoked_at" timestamp with time zone,
  "created_by_patient_id" bigint
);
alter table "public"."clinical_exam_document_shares" enable row level security;
alter table "public"."clinical_exam_document_shares" force row level security;

create table "public"."clinical_casts" (
  "id" bigint generated by default as identity not null,
  "patient_id" bigint not null,
  "attendance_id" bigint,
  "body_region" text not null,
  "laterality" text not null,
  "status" text default 'in_use'::text not null,
  "applied_at" timestamp with time zone not null,
  "applied_by" uuid not null,
  "expected_removal_at" timestamp with time zone not null,
  "application_notes" text,
  "removed_at" timestamp with time zone,
  "removed_by" uuid,
  "removal_notes" text,
  "cancelled_at" timestamp with time zone,
  "cancelled_by" uuid,
  "cancellation_reason" text,
  "created_by" uuid not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."clinical_casts" enable row level security;
alter table "public"."clinical_casts" force row level security;

create table "public"."patient_portal_sessions" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" bigint not null,
  "token_hash" text not null,
  "created_at" timestamp with time zone default now() not null,
  "expires_at" timestamp with time zone not null,
  "revoked_at" timestamp with time zone
);
alter table "public"."patient_portal_sessions" enable row level security;
alter table "public"."patient_portal_sessions" force row level security;

create table "public"."patient_portal_login_attempts" (
  "id" bigint generated by default as identity not null,
  "patient_id" bigint,
  "passport_hash" text not null,
  "origin_hash" text not null,
  "client_hash" text,
  "succeeded" boolean default false not null,
  "blocked" boolean default false not null,
  "block_scope" text,
  "attempted_at" timestamp with time zone default now() not null
);
alter table "public"."patient_portal_login_attempts" enable row level security;
alter table "public"."patient_portal_login_attempts" force row level security;

create table "public"."dashboard_preferences" (
  "user_id" uuid not null,
  "config_version" smallint default 1 not null,
  "layout_json" jsonb not null,
  "hidden_widgets" jsonb default '[]'::jsonb not null,
  "shortcuts_json" jsonb default '[]'::jsonb not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."dashboard_preferences" enable row level security;
alter table "public"."dashboard_preferences" force row level security;

create table "public"."professional_identities" (
  "user_id" uuid not null,
  "crm_code" text not null,
  "registration_date" date not null,
  "signature_image_path" text,
  "rubric_image_path" text,
  "signature_file_size" integer,
  "rubric_file_size" integer,
  "signature_generated_at" timestamp with time zone,
  "signature_generated_by" uuid,
  "signature_regenerated_at" timestamp with time zone,
  "signature_regenerated_by" uuid,
  "signature_regeneration_reason" text,
  "identity_locked" boolean default true not null,
  "status" text default 'pending'::text not null,
  "generation_version" integer default 0 not null,
  "current_generation_id" uuid,
  "generation_operation" text,
  "generation_started_at" timestamp with time zone,
  "last_failure_code" text,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);
alter table "public"."professional_identities" enable row level security;
alter table "public"."professional_identities" force row level security;

create table "public"."partnerships" (
  "id" bigint generated by default as identity not null,
  "name" text not null,
  "status" text default 'active'::text not null,
  "notes" text,
  "responsible_patient_id" bigint,
  "responsible_assigned_at" timestamp with time zone,
  "responsible_assigned_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "created_by" uuid not null,
  "updated_at" timestamp with time zone default now() not null,
  "updated_by" uuid not null,
  "deactivated_at" timestamp with time zone,
  "deactivated_by" uuid,
  "deactivation_reason" text
);
alter table "public"."partnerships" enable row level security;
alter table "public"."partnerships" force row level security;

create table "public"."partnership_responsible_history" (
  "id" bigint generated by default as identity not null,
  "partnership_id" bigint not null,
  "previous_patient_id" bigint,
  "responsible_patient_id" bigint,
  "changed_at" timestamp with time zone default now() not null,
  "changed_by" uuid not null
);
alter table "public"."partnership_responsible_history" enable row level security;
alter table "public"."partnership_responsible_history" force row level security;

create table "public"."partnership_status_history" (
  "id" bigint generated by default as identity not null,
  "partnership_id" bigint not null,
  "previous_status" text,
  "status" text not null,
  "reason" text,
  "changed_at" timestamp with time zone default now() not null,
  "changed_by" uuid not null
);
alter table "public"."partnership_status_history" enable row level security;
alter table "public"."partnership_status_history" force row level security;

create table "public"."patient_partnerships" (
  "id" bigint generated by default as identity not null,
  "patient_id" bigint not null,
  "partnership_id" bigint not null,
  "status" text default 'active'::text not null,
  "linked_at" timestamp with time zone default now() not null,
  "linked_by_type" text not null,
  "linked_by_user_id" uuid,
  "linked_by_patient_id" bigint,
  "unlinked_at" timestamp with time zone,
  "unlinked_by_type" text,
  "unlinked_by_user_id" uuid,
  "unlinked_by_patient_id" bigint,
  "unlink_reason" text
);
alter table "public"."patient_partnerships" enable row level security;
alter table "public"."patient_partnerships" force row level security;

create table "public"."partnership_pending_beneficiaries" (
  "id" bigint generated by default as identity not null,
  "partnership_id" bigint not null,
  "passport" text not null,
  "informed_name" text not null,
  "status" text default 'pending_registration'::text not null,
  "created_at" timestamp with time zone default now() not null,
  "source" text not null,
  "created_by_type" text not null,
  "created_by_user_id" uuid,
  "created_by_patient_id" bigint,
  "resolved_at" timestamp with time zone,
  "resolved_patient_id" bigint,
  "canceled_at" timestamp with time zone,
  "canceled_by_type" text,
  "canceled_by_user_id" uuid,
  "canceled_by_patient_id" bigint,
  "cancellation_reason" text
);
alter table "public"."partnership_pending_beneficiaries" enable row level security;
alter table "public"."partnership_pending_beneficiaries" force row level security;

-- Constraints canônicas.
alter table "public"."attendance_items" add constraint "attendance_items_attendance_id_fkey" FOREIGN KEY (attendance_id) REFERENCES attendances(id) ON DELETE CASCADE;
alter table "public"."attendance_items" add constraint "attendance_items_attendance_service_unique" UNIQUE (attendance_id, service_id);
alter table "public"."attendance_items" add constraint "attendance_items_discount_percent_check" CHECK (discount_percent >= 0::numeric AND discount_percent <= 100::numeric);
alter table "public"."attendance_items" add constraint "attendance_items_pkey" PRIMARY KEY (id);
alter table "public"."attendance_items" add constraint "attendance_items_quantity_check" CHECK (quantity >= 1 AND quantity <= 99);
alter table "public"."attendance_items" add constraint "attendance_items_service_id_fkey" FOREIGN KEY (service_id) REFERENCES service_catalog(id) ON DELETE RESTRICT;
alter table "public"."attendance_items" add constraint "attendance_items_service_name_check" CHECK (char_length(btrim(service_name)) >= 2 AND char_length(btrim(service_name)) <= 100);
alter table "public"."attendance_items" add constraint "attendance_items_unit_price_check" CHECK (unit_price >= 0::numeric);
alter table "public"."attendances" add constraint "attendances_cancellation_state_check" CHECK (status = 'completed'::text AND cancelled_by IS NULL AND cancelled_at IS NULL OR status = 'cancelled'::text AND cancelled_by IS NOT NULL AND cancelled_at IS NOT NULL);
alter table "public"."attendances" add constraint "attendances_cancelled_by_fkey" FOREIGN KEY (cancelled_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table "public"."attendances" add constraint "attendances_discount_check" CHECK (discount >= 0::numeric AND discount <= subtotal);
alter table "public"."attendances" add constraint "attendances_notes_check" CHECK (notes IS NULL OR char_length(notes) <= 1000);
alter table "public"."attendances" add constraint "attendances_partnership_id_fkey" FOREIGN KEY (partnership_id) REFERENCES partnerships(id) ON DELETE RESTRICT;
alter table "public"."attendances" add constraint "attendances_partnership_snapshot_check" CHECK (plan_code = 'parceiros_hp'::text AND (partnership_id IS NULL AND partnership_name IS NULL OR partnership_id IS NOT NULL AND char_length(btrim(partnership_name)) >= 2 AND char_length(btrim(partnership_name)) <= 120) OR plan_code IS DISTINCT FROM 'parceiros_hp'::text AND partnership_id IS NULL AND partnership_name IS NULL);
alter table "public"."attendances" add constraint "attendances_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."attendances" add constraint "attendances_patient_name_check" CHECK (char_length(btrim(patient_name)) >= 2 AND char_length(btrim(patient_name)) <= 100);
alter table "public"."attendances" add constraint "attendances_patient_passport_check" CHECK (patient_id IS NULL AND patient_passport = '—'::text OR patient_id IS NOT NULL AND patient_passport ~ '^[0-9]{1,4}$'::text);
alter table "public"."attendances" add constraint "attendances_performed_by_fkey" FOREIGN KEY (performed_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table "public"."attendances" add constraint "attendances_pkey" PRIMARY KEY (id);
alter table "public"."attendances" add constraint "attendances_plan_snapshot_check" CHECK (plan_code IS NULL AND plan_name IS NULL OR plan_code IS NOT NULL AND char_length(btrim(plan_name)) >= 2 AND char_length(btrim(plan_name)) <= 80);
alter table "public"."attendances" add constraint "attendances_status_check" CHECK (status = ANY (ARRAY['completed'::text, 'cancelled'::text]));
alter table "public"."attendances" add constraint "attendances_subtotal_check" CHECK (subtotal >= 0::numeric);
alter table "public"."audit_logs" add constraint "audit_logs_actor_passport_format" CHECK (actor_passport IS NULL OR actor_passport ~ '^[0-9]{1,4}$'::text);
alter table "public"."audit_logs" add constraint "audit_logs_actor_user_id_fkey" FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table "public"."audit_logs" add constraint "audit_logs_pkey" PRIMARY KEY (id);
alter table "public"."benefit_plans" add constraint "benefit_plans_code_check" CHECK (code ~ '^[a-z0-9_]{2,48}$'::text);
alter table "public"."benefit_plans" add constraint "benefit_plans_name_check" CHECK (char_length(btrim(name)) >= 2 AND char_length(btrim(name)) <= 80);
alter table "public"."benefit_plans" add constraint "benefit_plans_name_key" UNIQUE (name);
alter table "public"."benefit_plans" add constraint "benefit_plans_pkey" PRIMARY KEY (code);
alter table "public"."benefit_plans" add constraint "benefit_plans_sort_order_check" CHECK (sort_order >= 1 AND sort_order <= 100);
alter table "public"."benefit_plans" add constraint "benefit_plans_sort_order_key" UNIQUE (sort_order);
alter table "public"."clinical_casts" add constraint "clinical_casts_application_actor_check" CHECK (applied_by = created_by);
alter table "public"."clinical_casts" add constraint "clinical_casts_application_notes_check" CHECK (application_notes IS NULL OR char_length(btrim(application_notes)) >= 2 AND char_length(btrim(application_notes)) <= 1000);
alter table "public"."clinical_casts" add constraint "clinical_casts_applied_by_fkey" FOREIGN KEY (applied_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_casts" add constraint "clinical_casts_attendance_id_fkey" FOREIGN KEY (attendance_id) REFERENCES attendances(id) ON DELETE RESTRICT;
alter table "public"."clinical_casts" add constraint "clinical_casts_body_region_check" CHECK (body_region = ANY (ARRAY['hand'::text, 'wrist'::text, 'forearm'::text, 'elbow'::text, 'arm'::text, 'foot'::text, 'ankle'::text, 'leg'::text, 'knee'::text, 'other'::text]));
alter table "public"."clinical_casts" add constraint "clinical_casts_cancellation_reason_check" CHECK (cancellation_reason IS NULL OR char_length(btrim(cancellation_reason)) >= 2 AND char_length(btrim(cancellation_reason)) <= 500);
alter table "public"."clinical_casts" add constraint "clinical_casts_cancelled_by_fkey" FOREIGN KEY (cancelled_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_casts" add constraint "clinical_casts_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_casts" add constraint "clinical_casts_expected_after_application_check" CHECK (expected_removal_at > applied_at);
alter table "public"."clinical_casts" add constraint "clinical_casts_laterality_check" CHECK (laterality = ANY (ARRAY['right'::text, 'left'::text, 'bilateral'::text, 'not_applicable'::text]));
alter table "public"."clinical_casts" add constraint "clinical_casts_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."clinical_casts" add constraint "clinical_casts_pkey" PRIMARY KEY (id);
alter table "public"."clinical_casts" add constraint "clinical_casts_removal_notes_check" CHECK (removal_notes IS NULL OR char_length(btrim(removal_notes)) >= 2 AND char_length(btrim(removal_notes)) <= 1000);
alter table "public"."clinical_casts" add constraint "clinical_casts_removed_by_fkey" FOREIGN KEY (removed_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_casts" add constraint "clinical_casts_state_check" CHECK (status = 'in_use'::text AND removed_at IS NULL AND removed_by IS NULL AND removal_notes IS NULL AND cancelled_at IS NULL AND cancelled_by IS NULL AND cancellation_reason IS NULL OR status = 'removed'::text AND removed_at IS NOT NULL AND removed_by IS NOT NULL AND removed_at >= applied_at AND cancelled_at IS NULL AND cancelled_by IS NULL AND cancellation_reason IS NULL OR status = 'cancelled'::text AND removed_at IS NULL AND removed_by IS NULL AND removal_notes IS NULL AND cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL AND cancellation_reason IS NOT NULL);
alter table "public"."clinical_casts" add constraint "clinical_casts_status_check" CHECK (status = ANY (ARRAY['in_use'::text, 'removed'::text, 'cancelled'::text]));
alter table "public"."clinical_exam_document_shares" add constraint "clinical_exam_document_shares_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_document_shares" add constraint "clinical_exam_document_shares_created_by_patient_id_fkey" FOREIGN KEY (created_by_patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_document_shares" add constraint "clinical_exam_document_shares_creator_check" CHECK (created_by IS NOT NULL AND created_by_patient_id IS NULL OR created_by IS NULL AND created_by_patient_id IS NOT NULL);
alter table "public"."clinical_exam_document_shares" add constraint "clinical_exam_document_shares_document_id_fkey" FOREIGN KEY (document_id) REFERENCES clinical_exam_documents(id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_document_shares" add constraint "clinical_exam_document_shares_exam_id_fkey" FOREIGN KEY (exam_id) REFERENCES clinical_exams(id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_document_shares" add constraint "clinical_exam_document_shares_pkey" PRIMARY KEY (id);
alter table "public"."clinical_exam_document_shares" add constraint "clinical_exam_document_shares_revocation_pair_check" CHECK (revoked_by IS NULL AND revoked_at IS NULL OR revoked_by IS NOT NULL AND revoked_at IS NOT NULL);
alter table "public"."clinical_exam_document_shares" add constraint "clinical_exam_document_shares_revoked_by_fkey" FOREIGN KEY (revoked_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_documents" add constraint "clinical_exam_documents_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_documents" add constraint "clinical_exam_documents_created_by_patient_id_fkey" FOREIGN KEY (created_by_patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_documents" add constraint "clinical_exam_documents_creator_check" CHECK (created_by IS NOT NULL AND created_by_patient_id IS NULL OR created_by IS NULL AND created_by_patient_id IS NOT NULL);
alter table "public"."clinical_exam_documents" add constraint "clinical_exam_documents_exam_id_fkey" FOREIGN KEY (exam_id) REFERENCES clinical_exams(id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_documents" add constraint "clinical_exam_documents_height_check" CHECK (pixel_height >= 400 AND pixel_height <= 14000);
alter table "public"."clinical_exam_documents" add constraint "clinical_exam_documents_pkey" PRIMARY KEY (id);
alter table "public"."clinical_exam_documents" add constraint "clinical_exam_documents_png_mime_check" CHECK (mime_type = 'image/png'::text);
alter table "public"."clinical_exam_documents" add constraint "clinical_exam_documents_render_version_check" CHECK (render_version = ANY (ARRAY['exam-document-png-v1'::text, 'exam-document-png-v2'::text, 'exam-document-png-v3'::text, 'exam-document-png-v4'::text]));
alter table "public"."clinical_exam_documents" add constraint "clinical_exam_documents_size_check" CHECK (file_size >= 1 AND file_size <= 12582912);
alter table "public"."clinical_exam_documents" add constraint "clinical_exam_documents_storage_path_check" CHECK (storage_path ~ (('^clinical-exams/'::text || exam_id::text) || '/documents/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.png$'::text));
alter table "public"."clinical_exam_documents" add constraint "clinical_exam_documents_storage_path_key" UNIQUE (storage_path);
alter table "public"."clinical_exam_documents" add constraint "clinical_exam_documents_width_check" CHECK (pixel_width >= 900 AND pixel_width <= 1400);
alter table "public"."clinical_exam_images" add constraint "clinical_exam_images_caption_check" CHECK (caption IS NULL OR char_length(btrim(caption)) >= 1 AND char_length(btrim(caption)) <= 500);
alter table "public"."clinical_exam_images" add constraint "clinical_exam_images_exam_id_fkey" FOREIGN KEY (exam_id) REFERENCES clinical_exams(id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_images" add constraint "clinical_exam_images_filename_check" CHECK (char_length(btrim(original_filename)) >= 1 AND char_length(btrim(original_filename)) <= 240);
alter table "public"."clinical_exam_images" add constraint "clinical_exam_images_mime_check" CHECK (mime_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text]));
alter table "public"."clinical_exam_images" add constraint "clinical_exam_images_path_check" CHECK (storage_path ~ '^clinical-exams/[0-9]+/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'::text);
alter table "public"."clinical_exam_images" add constraint "clinical_exam_images_pkey" PRIMARY KEY (id);
alter table "public"."clinical_exam_images" add constraint "clinical_exam_images_removal_check" CHECK (removed_at IS NULL AND removed_by IS NULL OR removed_at IS NOT NULL AND removed_by IS NOT NULL);
alter table "public"."clinical_exam_images" add constraint "clinical_exam_images_removed_by_fkey" FOREIGN KEY (removed_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_images" add constraint "clinical_exam_images_size_check" CHECK (file_size >= 1 AND file_size <= 10485760);
alter table "public"."clinical_exam_images" add constraint "clinical_exam_images_sort_check" CHECK (sort_order >= 0 AND sort_order <= 100000);
alter table "public"."clinical_exam_images" add constraint "clinical_exam_images_source_check" CHECK (source = ANY (ARRAY['upload'::text, 'ai_generated'::text]));
alter table "public"."clinical_exam_images" add constraint "clinical_exam_images_storage_path_key" UNIQUE (storage_path);
alter table "public"."clinical_exam_images" add constraint "clinical_exam_images_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_report_versions" add constraint "clinical_exam_report_versions_decision_check" CHECK (decision = ANY (ARRAY['pending'::text, 'returned'::text, 'approved'::text]));
alter table "public"."clinical_exam_report_versions" add constraint "clinical_exam_report_versions_exam_id_fkey" FOREIGN KEY (exam_id) REFERENCES clinical_exams(id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_report_versions" add constraint "clinical_exam_report_versions_exam_id_version_number_key" UNIQUE (exam_id, version_number);
alter table "public"."clinical_exam_report_versions" add constraint "clinical_exam_report_versions_number_check" CHECK (version_number > 0);
alter table "public"."clinical_exam_report_versions" add constraint "clinical_exam_report_versions_pkey" PRIMARY KEY (id);
alter table "public"."clinical_exam_report_versions" add constraint "clinical_exam_report_versions_reason_check" CHECK (review_reason IS NULL OR char_length(btrim(review_reason)) >= 2 AND char_length(btrim(review_reason)) <= 2000);
alter table "public"."clinical_exam_report_versions" add constraint "clinical_exam_report_versions_review_check" CHECK (decision = 'pending'::text AND reviewed_by IS NULL AND reviewed_at IS NULL AND review_reason IS NULL OR decision = 'returned'::text AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL AND review_reason IS NOT NULL OR decision = 'approved'::text AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL AND review_reason IS NULL);
alter table "public"."clinical_exam_report_versions" add constraint "clinical_exam_report_versions_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_report_versions" add constraint "clinical_exam_report_versions_snapshot_check" CHECK (jsonb_typeof(snapshot) = 'object'::text);
alter table "public"."clinical_exam_report_versions" add constraint "clinical_exam_report_versions_submitted_by_fkey" FOREIGN KEY (submitted_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_status_history" add constraint "clinical_exam_history_from_status_check" CHECK (from_status IS NULL OR (from_status = ANY (ARRAY['requested'::text, 'in_progress'::text, 'awaiting_review'::text, 'completed'::text])));
alter table "public"."clinical_exam_status_history" add constraint "clinical_exam_history_note_check" CHECK (note IS NULL OR char_length(btrim(note)) >= 2 AND char_length(btrim(note)) <= 2000);
alter table "public"."clinical_exam_status_history" add constraint "clinical_exam_history_to_status_check" CHECK (to_status = ANY (ARRAY['requested'::text, 'in_progress'::text, 'awaiting_review'::text, 'completed'::text]));
alter table "public"."clinical_exam_status_history" add constraint "clinical_exam_status_history_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_status_history" add constraint "clinical_exam_status_history_exam_id_fkey" FOREIGN KEY (exam_id) REFERENCES clinical_exams(id) ON DELETE RESTRICT;
alter table "public"."clinical_exam_status_history" add constraint "clinical_exam_status_history_pkey" PRIMARY KEY (id);
alter table "public"."clinical_exams" add constraint "clinical_exams_attendance_id_fkey" FOREIGN KEY (attendance_id) REFERENCES attendances(id) ON DELETE RESTRICT;
alter table "public"."clinical_exams" add constraint "clinical_exams_conclusion_check" CHECK (conclusion IS NULL OR char_length(btrim(conclusion)) >= 2 AND char_length(btrim(conclusion)) <= 4000);
alter table "public"."clinical_exams" add constraint "clinical_exams_context_check" CHECK (clinical_context IS NULL OR char_length(btrim(clinical_context)) >= 2 AND char_length(btrim(clinical_context)) <= 4000);
alter table "public"."clinical_exams" add constraint "clinical_exams_correction_reason_check" CHECK (correction_reason IS NULL OR char_length(btrim(correction_reason)) >= 2 AND char_length(btrim(correction_reason)) <= 2000);
alter table "public"."clinical_exams" add constraint "clinical_exams_exam_type_id_fkey" FOREIGN KEY (exam_type_id) REFERENCES exam_types(id) ON DELETE RESTRICT;
alter table "public"."clinical_exams" add constraint "clinical_exams_final_report_snapshot_check" CHECK (final_report_snapshot IS NULL OR jsonb_typeof(final_report_snapshot) = 'object'::text);
alter table "public"."clinical_exams" add constraint "clinical_exams_final_report_status_check" CHECK (status = 'completed'::text AND final_report_snapshot IS NOT NULL OR status <> 'completed'::text AND final_report_snapshot IS NULL);
alter table "public"."clinical_exams" add constraint "clinical_exams_findings_check" CHECK (findings IS NULL OR char_length(btrim(findings)) >= 2 AND char_length(btrim(findings)) <= 8000);
alter table "public"."clinical_exams" add constraint "clinical_exams_indication_check" CHECK (char_length(btrim(indication)) >= 2 AND char_length(btrim(indication)) <= 2000);
alter table "public"."clinical_exams" add constraint "clinical_exams_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."clinical_exams" add constraint "clinical_exams_pkey" PRIMARY KEY (id);
alter table "public"."clinical_exams" add constraint "clinical_exams_requested_by_fkey" FOREIGN KEY (requested_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_exams" add constraint "clinical_exams_responsible_professional_id_fkey" FOREIGN KEY (responsible_professional_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_exams" add constraint "clinical_exams_result_data_check" CHECK (jsonb_typeof(result_data) = 'object'::text);
alter table "public"."clinical_exams" add constraint "clinical_exams_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."clinical_exams" add constraint "clinical_exams_status_check" CHECK (status = ANY (ARRAY['requested'::text, 'in_progress'::text, 'awaiting_review'::text, 'completed'::text]));
alter table "public"."clinical_exams" add constraint "clinical_exams_technique_check" CHECK (technique IS NULL OR char_length(btrim(technique)) >= 2 AND char_length(btrim(technique)) <= 4000);
alter table "public"."clinical_exams" add constraint "clinical_exams_timeline_check" CHECK (status = 'requested'::text AND started_at IS NULL AND submitted_for_review_at IS NULL AND completed_at IS NULL AND reviewed_by IS NULL OR status = 'in_progress'::text AND started_at IS NOT NULL AND submitted_for_review_at IS NULL AND completed_at IS NULL AND reviewed_by IS NULL OR status = 'awaiting_review'::text AND started_at IS NOT NULL AND submitted_for_review_at IS NOT NULL AND completed_at IS NULL AND reviewed_by IS NULL OR status = 'completed'::text AND started_at IS NOT NULL AND submitted_for_review_at IS NOT NULL AND completed_at IS NOT NULL AND reviewed_by IS NOT NULL);
alter table "public"."courses" add constraint "courses_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."courses" add constraint "courses_description_check" CHECK (char_length(description) <= 4000);
alter table "public"."courses" add constraint "courses_name_check" CHECK (char_length(btrim(name)) >= 2 AND char_length(btrim(name)) <= 120);
alter table "public"."courses" add constraint "courses_pkey" PRIMARY KEY (id);
alter table "public"."courses" add constraint "courses_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."dashboard_preferences" add constraint "dashboard_preferences_config_version_check" CHECK (config_version = 1);
alter table "public"."dashboard_preferences" add constraint "dashboard_preferences_hidden_widgets_check" CHECK (jsonb_typeof(hidden_widgets) = 'array'::text AND jsonb_array_length(hidden_widgets) <= 7);
alter table "public"."dashboard_preferences" add constraint "dashboard_preferences_layout_json_check" CHECK (jsonb_typeof(layout_json) = 'object'::text AND pg_column_size(layout_json) <= 28672);
alter table "public"."dashboard_preferences" add constraint "dashboard_preferences_pkey" PRIMARY KEY (user_id);
alter table "public"."dashboard_preferences" add constraint "dashboard_preferences_shortcuts_json_check" CHECK (jsonb_typeof(shortcuts_json) = 'array'::text AND jsonb_array_length(shortcuts_json) <= 19);
alter table "public"."dashboard_preferences" add constraint "dashboard_preferences_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(user_id) ON DELETE CASCADE;
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_error_check" CHECK (error_code IS NULL OR char_length(error_code) >= 2 AND char_length(error_code) <= 80);
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_exam_id_fkey" FOREIGN KEY (exam_id) REFERENCES clinical_exams(id) ON DELETE RESTRICT;
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_idempotency_key_key" UNIQUE (idempotency_key);
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_image_config_check" CHECK (generation_type <> 'generate_image'::text AND image_quality IS NULL AND image_size IS NULL AND image_count IS NULL AND draft_storage_path IS NULL AND draft_mime_type IS NULL AND draft_file_size IS NULL AND official_image_id IS NULL OR generation_type = 'generate_image'::text AND image_quality = 'low'::text AND image_size = '1024x1024'::text AND image_count = 1 AND (draft_storage_path IS NULL OR draft_storage_path ~ (('^clinical-exams/'::text || exam_id::text) || '/ai-drafts/[0-9a-f-]{36}\.png$'::text)) AND (draft_mime_type IS NULL OR draft_mime_type = 'image/png'::text) AND (draft_file_size IS NULL OR draft_file_size >= 1 AND draft_file_size <= 10485760));
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_model_check" CHECK (generation_type = 'generate_image'::text AND model = 'gpt-image-2'::text OR generation_type <> 'generate_image'::text AND model = 'gpt-5.6-luna'::text);
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_official_image_id_fkey" FOREIGN KEY (official_image_id) REFERENCES clinical_exam_images(id) ON DELETE RESTRICT;
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_payload_check" CHECK (suggestion_payload IS NULL OR jsonb_typeof(suggestion_payload) = 'object'::text);
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_pkey" PRIMARY KEY (id);
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_prompt_check" CHECK (generation_type = 'generate_image'::text AND (prompt_version = ANY (ARRAY['exam-image-rp-v1'::text, 'exam-image-rp-v2'::text, 'exam-image-clinical-v3'::text])) OR generation_type = 'generate_exam'::text AND (prompt_version = ANY (ARRAY['exam-rp-luna-v4'::text, 'exam-clinical-exam-v5'::text])) OR generation_type = 'generate_report'::text AND (prompt_version = ANY (ARRAY['exam-rp-luna-v1'::text, 'exam-rp-luna-v2'::text, 'exam-rp-luna-v3'::text, 'exam-clinical-report-v4'::text])) OR generation_type = 'generate_lab_results'::text AND (prompt_version = ANY (ARRAY['exam-rp-luna-v1'::text, 'exam-rp-luna-v2'::text, 'exam-rp-luna-v3'::text, 'exam-clinical-lab-v3'::text])));
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_reasoning_check" CHECK (reasoning_effort = 'low'::text);
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_requested_by_fkey" FOREIGN KEY (requested_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_response_id_check" CHECK (openai_response_id IS NULL OR char_length(openai_response_id) >= 3 AND char_length(openai_response_id) <= 200);
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_source_image_check" CHECK (NOT (source_image_generation_id IS NOT NULL AND source_image_id IS NOT NULL) AND (generation_type = 'generate_report'::text OR source_image_generation_id IS NULL AND source_image_id IS NULL));
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_source_image_generation_fkey" FOREIGN KEY (source_image_generation_id) REFERENCES exam_ai_generations(id) ON DELETE RESTRICT;
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_source_image_id_fkey" FOREIGN KEY (source_image_id) REFERENCES clinical_exam_images(id) ON DELETE RESTRICT;
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_state_check" CHECK (status = 'requested'::text AND suggestion_payload IS NULL AND openai_response_id IS NULL AND input_tokens IS NULL AND output_tokens IS NULL AND total_tokens IS NULL AND completed_at IS NULL AND failed_at IS NULL AND applied_at IS NULL AND discarded_at IS NULL OR status = 'completed'::text AND suggestion_payload IS NOT NULL AND openai_response_id IS NOT NULL AND input_tokens IS NOT NULL AND output_tokens IS NOT NULL AND total_tokens IS NOT NULL AND completed_at IS NOT NULL AND failed_at IS NULL AND applied_at IS NULL AND discarded_at IS NULL OR status = 'failed'::text AND suggestion_payload IS NULL AND error_code IS NOT NULL AND failed_at IS NOT NULL AND applied_at IS NULL AND discarded_at IS NULL OR status = 'applied'::text AND suggestion_payload IS NOT NULL AND openai_response_id IS NOT NULL AND input_tokens IS NOT NULL AND output_tokens IS NOT NULL AND total_tokens IS NOT NULL AND completed_at IS NOT NULL AND applied_at IS NOT NULL AND failed_at IS NULL AND discarded_at IS NULL OR status = 'discarded'::text AND suggestion_payload IS NOT NULL AND openai_response_id IS NOT NULL AND input_tokens IS NOT NULL AND output_tokens IS NOT NULL AND total_tokens IS NOT NULL AND completed_at IS NOT NULL AND discarded_at IS NOT NULL AND failed_at IS NULL AND applied_at IS NULL);
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_status_check" CHECK (status = ANY (ARRAY['requested'::text, 'completed'::text, 'failed'::text, 'applied'::text, 'discarded'::text]));
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_token_check" CHECK ((input_tokens IS NULL OR input_tokens >= 0) AND (output_tokens IS NULL OR output_tokens >= 0) AND (total_tokens IS NULL OR total_tokens >= 0));
alter table "public"."exam_ai_generations" add constraint "exam_ai_generations_type_check" CHECK (generation_type = ANY (ARRAY['generate_lab_results'::text, 'generate_report'::text, 'generate_image'::text, 'generate_exam'::text]));
alter table "public"."exam_categories" add constraint "exam_categories_code_check" CHECK (code ~ '^[a-z0-9_]{2,48}$'::text);
alter table "public"."exam_categories" add constraint "exam_categories_code_key" UNIQUE (code);
alter table "public"."exam_categories" add constraint "exam_categories_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."exam_categories" add constraint "exam_categories_name_check" CHECK (char_length(btrim(name)) >= 2 AND char_length(btrim(name)) <= 80);
alter table "public"."exam_categories" add constraint "exam_categories_pkey" PRIMARY KEY (id);
alter table "public"."exam_categories" add constraint "exam_categories_sort_order_check" CHECK (sort_order >= '-10000'::integer AND sort_order <= 10000);
alter table "public"."exam_categories" add constraint "exam_categories_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."exam_types" add constraint "exam_types_category_id_fkey" FOREIGN KEY (category_id) REFERENCES exam_categories(id) ON DELETE RESTRICT;
alter table "public"."exam_types" add constraint "exam_types_code_check" CHECK (code ~ '^[a-z0-9_]{2,64}$'::text);
alter table "public"."exam_types" add constraint "exam_types_code_key" UNIQUE (code);
alter table "public"."exam_types" add constraint "exam_types_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."exam_types" add constraint "exam_types_description_check" CHECK (description IS NULL OR char_length(btrim(description)) >= 2 AND char_length(btrim(description)) <= 1000);
alter table "public"."exam_types" add constraint "exam_types_name_check" CHECK (char_length(btrim(name)) >= 2 AND char_length(btrim(name)) <= 100);
alter table "public"."exam_types" add constraint "exam_types_pkey" PRIMARY KEY (id);
alter table "public"."exam_types" add constraint "exam_types_result_config_check" CHECK (jsonb_typeof(result_config) = 'object'::text);
alter table "public"."exam_types" add constraint "exam_types_sort_order_check" CHECK (sort_order >= '-10000'::integer AND sort_order <= 10000);
alter table "public"."exam_types" add constraint "exam_types_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."notification_reads" add constraint "notification_reads_notification_id_fkey" FOREIGN KEY (notification_id) REFERENCES notifications(id) ON DELETE CASCADE;
alter table "public"."notification_reads" add constraint "notification_reads_pkey" PRIMARY KEY (notification_id, user_id);
alter table "public"."notification_reads" add constraint "notification_reads_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table "public"."notifications" add constraint "notifications_action_url_check" CHECK (action_url IS NULL OR action_url ~ '^/[A-Za-z0-9_/?#=&.-]*$'::text AND char_length(action_url) <= 240);
alter table "public"."notifications" add constraint "notifications_archive_check" CHECK (archived_at IS NULL AND archived_by IS NULL OR archived_at IS NOT NULL AND archived_by IS NOT NULL);
alter table "public"."notifications" add constraint "notifications_archived_by_fkey" FOREIGN KEY (archived_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table "public"."notifications" add constraint "notifications_audience_check" CHECK (audience IS NULL OR (audience = ANY (ARRAY['all'::text, 'directors'::text, 'employees'::text])));
alter table "public"."notifications" add constraint "notifications_body_check" CHECK (char_length(btrim(body)) >= 10 AND char_length(btrim(body)) <= 2000);
alter table "public"."notifications" add constraint "notifications_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table "public"."notifications" add constraint "notifications_expiration_check" CHECK (expires_at IS NULL OR expires_at > created_at);
alter table "public"."notifications" add constraint "notifications_kind_check" CHECK (kind = ANY (ARRAY['personal'::text, 'system'::text, 'announcement'::text]));
alter table "public"."notifications" add constraint "notifications_pkey" PRIMARY KEY (id);
alter table "public"."notifications" add constraint "notifications_priority_check" CHECK (priority = ANY (ARRAY['normal'::text, 'important'::text, 'urgent'::text]));
alter table "public"."notifications" add constraint "notifications_recipient_id_fkey" FOREIGN KEY (recipient_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table "public"."notifications" add constraint "notifications_required_permission_fkey" FOREIGN KEY (required_permission) REFERENCES system_permissions(code) ON DELETE RESTRICT;
alter table "public"."notifications" add constraint "notifications_resolution_check" CHECK (resolved_at IS NULL AND resolved_by IS NULL OR resolved_at IS NOT NULL);
alter table "public"."notifications" add constraint "notifications_resolved_by_fkey" FOREIGN KEY (resolved_by) REFERENCES profiles(user_id) ON DELETE SET NULL;
alter table "public"."notifications" add constraint "notifications_scope_check" CHECK (kind = 'personal'::text AND recipient_id IS NOT NULL AND audience IS NULL OR (kind = ANY (ARRAY['system'::text, 'announcement'::text])) AND recipient_id IS NULL AND audience IS NOT NULL);
alter table "public"."notifications" add constraint "notifications_source_pair_check" CHECK (source_type IS NULL AND source_id IS NULL OR char_length(btrim(source_type)) >= 2 AND char_length(btrim(source_type)) <= 60 AND char_length(btrim(source_id)) >= 1 AND char_length(btrim(source_id)) <= 100);
alter table "public"."notifications" add constraint "notifications_title_check" CHECK (char_length(btrim(title)) >= 4 AND char_length(btrim(title)) <= 120);
alter table "public"."partnership_pending_beneficiaries" add constraint "partnership_pending_beneficiaries_canceled_by_patient_id_fkey" FOREIGN KEY (canceled_by_patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."partnership_pending_beneficiaries" add constraint "partnership_pending_beneficiaries_canceled_by_user_id_fkey" FOREIGN KEY (canceled_by_user_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."partnership_pending_beneficiaries" add constraint "partnership_pending_beneficiaries_created_by_patient_id_fkey" FOREIGN KEY (created_by_patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."partnership_pending_beneficiaries" add constraint "partnership_pending_beneficiaries_created_by_user_id_fkey" FOREIGN KEY (created_by_user_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."partnership_pending_beneficiaries" add constraint "partnership_pending_beneficiaries_partnership_id_fkey" FOREIGN KEY (partnership_id) REFERENCES partnerships(id) ON DELETE RESTRICT;
alter table "public"."partnership_pending_beneficiaries" add constraint "partnership_pending_beneficiaries_pkey" PRIMARY KEY (id);
alter table "public"."partnership_pending_beneficiaries" add constraint "partnership_pending_beneficiaries_resolved_patient_id_fkey" FOREIGN KEY (resolved_patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."partnership_pending_beneficiaries" add constraint "partnership_pending_canceled_origin_check" CHECK (canceled_by_type IS NULL OR canceled_by_type = 'professional'::text AND canceled_by_user_id IS NOT NULL AND canceled_by_patient_id IS NULL OR canceled_by_type = 'partnership_responsible'::text AND canceled_by_user_id IS NULL AND canceled_by_patient_id IS NOT NULL OR canceled_by_type = 'system'::text AND canceled_by_user_id IS NULL AND canceled_by_patient_id IS NULL);
alter table "public"."partnership_pending_beneficiaries" add constraint "partnership_pending_created_origin_check" CHECK (created_by_type = 'professional'::text AND created_by_user_id IS NOT NULL AND created_by_patient_id IS NULL OR created_by_type = 'partnership_responsible'::text AND created_by_user_id IS NULL AND created_by_patient_id IS NOT NULL OR created_by_type = 'system'::text AND created_by_user_id IS NULL AND created_by_patient_id IS NULL);
alter table "public"."partnership_pending_beneficiaries" add constraint "partnership_pending_name_check" CHECK (char_length(btrim(informed_name)) >= 2 AND char_length(btrim(informed_name)) <= 120);
alter table "public"."partnership_pending_beneficiaries" add constraint "partnership_pending_passport_check" CHECK (passport ~ '^[0-9]{1,4}$'::text);
alter table "public"."partnership_pending_beneficiaries" add constraint "partnership_pending_resolution_check" CHECK ((status = ANY (ARRAY['pending_registration'::text, 'name_review'::text])) AND resolved_at IS NULL AND resolved_patient_id IS NULL AND canceled_at IS NULL AND canceled_by_type IS NULL AND canceled_by_user_id IS NULL AND canceled_by_patient_id IS NULL AND cancellation_reason IS NULL OR status = 'resolved'::text AND resolved_at IS NOT NULL AND resolved_patient_id IS NOT NULL AND canceled_at IS NULL AND canceled_by_type IS NULL AND canceled_by_user_id IS NULL AND canceled_by_patient_id IS NULL AND cancellation_reason IS NULL OR status = 'canceled'::text AND resolved_at IS NULL AND resolved_patient_id IS NULL AND canceled_at IS NOT NULL AND (canceled_by_type = ANY (ARRAY['professional'::text, 'partnership_responsible'::text, 'system'::text])) AND char_length(btrim(cancellation_reason)) >= 2 AND char_length(btrim(cancellation_reason)) <= 500);
alter table "public"."partnership_pending_beneficiaries" add constraint "partnership_pending_source_check" CHECK (source = ANY (ARRAY['individual'::text, 'batch'::text, 'automatic'::text]));
alter table "public"."partnership_pending_beneficiaries" add constraint "partnership_pending_status_check" CHECK (status = ANY (ARRAY['pending_registration'::text, 'name_review'::text, 'resolved'::text, 'canceled'::text]));
alter table "public"."partnership_responsible_history" add constraint "partnership_responsible_history_change_check" CHECK (previous_patient_id IS DISTINCT FROM responsible_patient_id);
alter table "public"."partnership_responsible_history" add constraint "partnership_responsible_history_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."partnership_responsible_history" add constraint "partnership_responsible_history_partnership_id_fkey" FOREIGN KEY (partnership_id) REFERENCES partnerships(id) ON DELETE RESTRICT;
alter table "public"."partnership_responsible_history" add constraint "partnership_responsible_history_pkey" PRIMARY KEY (id);
alter table "public"."partnership_responsible_history" add constraint "partnership_responsible_history_previous_patient_id_fkey" FOREIGN KEY (previous_patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."partnership_responsible_history" add constraint "partnership_responsible_history_responsible_patient_id_fkey" FOREIGN KEY (responsible_patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."partnership_status_history" add constraint "partnership_status_history_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."partnership_status_history" add constraint "partnership_status_history_partnership_id_fkey" FOREIGN KEY (partnership_id) REFERENCES partnerships(id) ON DELETE RESTRICT;
alter table "public"."partnership_status_history" add constraint "partnership_status_history_pkey" PRIMARY KEY (id);
alter table "public"."partnership_status_history" add constraint "partnership_status_history_previous_check" CHECK (previous_status IS NULL OR (previous_status = ANY (ARRAY['active'::text, 'inactive'::text])));
alter table "public"."partnership_status_history" add constraint "partnership_status_history_reason_check" CHECK (reason IS NULL OR char_length(btrim(reason)) >= 2 AND char_length(btrim(reason)) <= 500);
alter table "public"."partnership_status_history" add constraint "partnership_status_history_status_check" CHECK (status = ANY (ARRAY['active'::text, 'inactive'::text]));
alter table "public"."partnerships" add constraint "partnerships_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."partnerships" add constraint "partnerships_deactivated_by_fkey" FOREIGN KEY (deactivated_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."partnerships" add constraint "partnerships_deactivation_check" CHECK (status = 'active'::text AND deactivated_at IS NULL AND deactivated_by IS NULL AND deactivation_reason IS NULL OR status = 'inactive'::text AND deactivated_at IS NOT NULL AND deactivated_by IS NOT NULL AND char_length(btrim(deactivation_reason)) >= 2 AND char_length(btrim(deactivation_reason)) <= 500);
alter table "public"."partnerships" add constraint "partnerships_name_check" CHECK (char_length(btrim(name)) >= 2 AND char_length(btrim(name)) <= 120);
alter table "public"."partnerships" add constraint "partnerships_notes_check" CHECK (notes IS NULL OR char_length(btrim(notes)) >= 2 AND char_length(btrim(notes)) <= 2000);
alter table "public"."partnerships" add constraint "partnerships_pkey" PRIMARY KEY (id);
alter table "public"."partnerships" add constraint "partnerships_responsible_assigned_by_fkey" FOREIGN KEY (responsible_assigned_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."partnerships" add constraint "partnerships_responsible_assignment_check" CHECK (responsible_patient_id IS NULL AND responsible_assigned_at IS NULL AND responsible_assigned_by IS NULL OR responsible_patient_id IS NOT NULL AND responsible_assigned_at IS NOT NULL AND responsible_assigned_by IS NOT NULL);
alter table "public"."partnerships" add constraint "partnerships_responsible_patient_id_fkey" FOREIGN KEY (responsible_patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."partnerships" add constraint "partnerships_status_check" CHECK (status = ANY (ARRAY['active'::text, 'inactive'::text]));
alter table "public"."partnerships" add constraint "partnerships_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."patient_health_plan_requests" add constraint "patient_health_plan_requests_attendance_id_fkey" FOREIGN KEY (attendance_id) REFERENCES attendances(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
alter table "public"."patient_health_plan_requests" add constraint "patient_health_plan_requests_attendance_id_key" UNIQUE (attendance_id);
alter table "public"."patient_health_plan_requests" add constraint "patient_health_plan_requests_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
alter table "public"."patient_health_plan_requests" add constraint "patient_health_plan_requests_pkey" PRIMARY KEY (id);
alter table "public"."patient_health_plan_requests" add constraint "patient_health_plan_requests_resolution_check" CHECK (status = 'pending'::text AND reviewed_by IS NULL AND reviewed_at IS NULL AND rejection_reason IS NULL AND coverage_start IS NULL AND coverage_end IS NULL OR status = 'approved'::text AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL AND rejection_reason IS NULL AND coverage_start IS NOT NULL AND coverage_end IS NOT NULL AND coverage_end > coverage_start OR status = 'rejected'::text AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL AND char_length(btrim(rejection_reason)) >= 10 AND char_length(btrim(rejection_reason)) <= 2000 AND coverage_start IS NULL AND coverage_end IS NULL);
alter table "public"."patient_health_plan_requests" add constraint "patient_health_plan_requests_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES profiles(user_id) ON UPDATE RESTRICT ON DELETE SET NULL;
alter table "public"."patient_health_plan_requests" add constraint "patient_health_plan_requests_status_check" CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text]));
alter table "public"."patient_partnerships" add constraint "patient_partnerships_linked_by_patient_id_fkey" FOREIGN KEY (linked_by_patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."patient_partnerships" add constraint "patient_partnerships_linked_by_user_id_fkey" FOREIGN KEY (linked_by_user_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."patient_partnerships" add constraint "patient_partnerships_linked_origin_check" CHECK (linked_by_type = 'professional'::text AND linked_by_user_id IS NOT NULL AND linked_by_patient_id IS NULL OR linked_by_type = 'partnership_responsible'::text AND linked_by_user_id IS NULL AND linked_by_patient_id IS NOT NULL OR linked_by_type = 'system'::text AND linked_by_user_id IS NULL AND linked_by_patient_id IS NULL);
alter table "public"."patient_partnerships" add constraint "patient_partnerships_partnership_id_fkey" FOREIGN KEY (partnership_id) REFERENCES partnerships(id) ON DELETE RESTRICT;
alter table "public"."patient_partnerships" add constraint "patient_partnerships_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."patient_partnerships" add constraint "patient_partnerships_pkey" PRIMARY KEY (id);
alter table "public"."patient_partnerships" add constraint "patient_partnerships_status_check" CHECK (status = ANY (ARRAY['active'::text, 'inactive'::text]));
alter table "public"."patient_partnerships" add constraint "patient_partnerships_unlinked_by_patient_id_fkey" FOREIGN KEY (unlinked_by_patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."patient_partnerships" add constraint "patient_partnerships_unlinked_by_user_id_fkey" FOREIGN KEY (unlinked_by_user_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."patient_partnerships" add constraint "patient_partnerships_unlinked_origin_check" CHECK (unlinked_by_type IS NULL OR unlinked_by_type = 'professional'::text AND unlinked_by_user_id IS NOT NULL AND unlinked_by_patient_id IS NULL OR unlinked_by_type = 'partnership_responsible'::text AND unlinked_by_user_id IS NULL AND unlinked_by_patient_id IS NOT NULL OR unlinked_by_type = 'system'::text AND unlinked_by_user_id IS NULL AND unlinked_by_patient_id IS NULL);
alter table "public"."patient_partnerships" add constraint "patient_partnerships_unlinked_state_check" CHECK (status = 'active'::text AND unlinked_at IS NULL AND unlinked_by_type IS NULL AND unlinked_by_user_id IS NULL AND unlinked_by_patient_id IS NULL AND unlink_reason IS NULL OR status = 'inactive'::text AND unlinked_at IS NOT NULL AND (unlinked_by_type = ANY (ARRAY['professional'::text, 'partnership_responsible'::text, 'system'::text])) AND char_length(btrim(unlink_reason)) >= 2 AND char_length(btrim(unlink_reason)) <= 500);
alter table "public"."patient_portal_login_attempts" add constraint "patient_portal_attempts_block_scope_check" CHECK (blocked AND (block_scope = ANY (ARRAY['passport'::text, 'origin'::text, 'both'::text])) OR NOT blocked AND block_scope IS NULL);
alter table "public"."patient_portal_login_attempts" add constraint "patient_portal_attempts_client_hash_check" CHECK (client_hash IS NULL OR client_hash ~ '^[0-9a-f]{64}$'::text);
alter table "public"."patient_portal_login_attempts" add constraint "patient_portal_attempts_origin_hash_check" CHECK (origin_hash ~ '^[0-9a-f]{64}$'::text);
alter table "public"."patient_portal_login_attempts" add constraint "patient_portal_attempts_outcome_check" CHECK (NOT (succeeded AND blocked));
alter table "public"."patient_portal_login_attempts" add constraint "patient_portal_attempts_passport_hash_check" CHECK (passport_hash ~ '^[0-9a-f]{64}$'::text);
alter table "public"."patient_portal_login_attempts" add constraint "patient_portal_login_attempts_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE SET NULL;
alter table "public"."patient_portal_login_attempts" add constraint "patient_portal_login_attempts_pkey" PRIMARY KEY (id);
alter table "public"."patient_portal_sessions" add constraint "patient_portal_sessions_expiry_check" CHECK (expires_at > created_at);
alter table "public"."patient_portal_sessions" add constraint "patient_portal_sessions_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE RESTRICT;
alter table "public"."patient_portal_sessions" add constraint "patient_portal_sessions_pkey" PRIMARY KEY (id);
alter table "public"."patient_portal_sessions" add constraint "patient_portal_sessions_revocation_check" CHECK (revoked_at IS NULL OR revoked_at >= created_at);
alter table "public"."patient_portal_sessions" add constraint "patient_portal_sessions_token_hash_check" CHECK (token_hash ~ '^[0-9a-f]{64}$'::text);
alter table "public"."patients" add constraint "patients_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table "public"."patients" add constraint "patients_emergency_contact_name_check" CHECK (emergency_contact_name IS NULL OR char_length(btrim(emergency_contact_name)) >= 2 AND char_length(btrim(emergency_contact_name)) <= 100);
alter table "public"."patients" add constraint "patients_emergency_contact_pair_check" CHECK ((emergency_contact_name IS NULL) = (emergency_contact_phone IS NULL));
alter table "public"."patients" add constraint "patients_emergency_contact_phone_check" CHECK (emergency_contact_phone IS NULL OR emergency_contact_phone ~ '^\(055\) [0-9]{3}-[0-9]{3}$'::text);
alter table "public"."patients" add constraint "patients_name_check" CHECK (char_length(btrim(name)) >= 2 AND char_length(btrim(name)) <= 100);
alter table "public"."patients" add constraint "patients_passport_check" CHECK (passport ~ '^[0-9]{1,4}$'::text);
alter table "public"."patients" add constraint "patients_phone_check" CHECK (phone ~ '^\([0-9]{3}\) [0-9]{3}-[0-9]{3}$'::text);
alter table "public"."patients" add constraint "patients_pkey" PRIMARY KEY (id);
alter table "public"."patients" add constraint "patients_plan_code_fkey" FOREIGN KEY (plan_code) REFERENCES benefit_plans(code) ON UPDATE RESTRICT ON DELETE RESTRICT;
alter table "public"."patients" add constraint "patients_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table "public"."plan_discounts" add constraint "plan_discounts_percent_check" CHECK (discount_percent >= 0::numeric AND discount_percent <= 100::numeric);
alter table "public"."plan_discounts" add constraint "plan_discounts_pkey" PRIMARY KEY (plan_code, service_id);
alter table "public"."plan_discounts" add constraint "plan_discounts_plan_code_fkey" FOREIGN KEY (plan_code) REFERENCES benefit_plans(code) ON UPDATE RESTRICT ON DELETE RESTRICT;
alter table "public"."plan_discounts" add constraint "plan_discounts_service_id_fkey" FOREIGN KEY (service_id) REFERENCES service_catalog(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
alter table "public"."plan_discounts" add constraint "plan_discounts_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table "public"."professional_identities" add constraint "professional_identities_crm_code_key" UNIQUE (crm_code);
alter table "public"."professional_identities" add constraint "professional_identities_crm_format" CHECK (crm_code ~ '^[0-9]{8}$'::text);
alter table "public"."professional_identities" add constraint "professional_identities_failure_code_check" CHECK (last_failure_code IS NULL OR char_length(last_failure_code) >= 1 AND char_length(last_failure_code) <= 80);
alter table "public"."professional_identities" add constraint "professional_identities_generation_operation" CHECK (generation_operation IS NULL OR (generation_operation = ANY (ARRAY['initial'::text, 'regenerate'::text, 'reprocess'::text])));
alter table "public"."professional_identities" add constraint "professional_identities_generation_version" CHECK (generation_version >= 0);
alter table "public"."professional_identities" add constraint "professional_identities_paths" CHECK (status = 'active'::text AND signature_image_path IS NOT NULL AND rubric_image_path IS NOT NULL AND signature_file_size IS NOT NULL AND rubric_file_size IS NOT NULL OR status <> 'active'::text);
alter table "public"."professional_identities" add constraint "professional_identities_pkey" PRIMARY KEY (user_id);
alter table "public"."professional_identities" add constraint "professional_identities_reason_check" CHECK (signature_regeneration_reason IS NULL OR char_length(btrim(signature_regeneration_reason)) >= 5 AND char_length(btrim(signature_regeneration_reason)) <= 500);
alter table "public"."professional_identities" add constraint "professional_identities_rubric_size" CHECK (rubric_file_size IS NULL OR rubric_file_size >= 32 AND rubric_file_size <= 5242880);
alter table "public"."professional_identities" add constraint "professional_identities_signature_generated_by_fkey" FOREIGN KEY (signature_generated_by) REFERENCES profiles(user_id) ON UPDATE CASCADE ON DELETE SET NULL;
alter table "public"."professional_identities" add constraint "professional_identities_signature_regenerated_by_fkey" FOREIGN KEY (signature_regenerated_by) REFERENCES profiles(user_id) ON UPDATE CASCADE ON DELETE SET NULL;
alter table "public"."professional_identities" add constraint "professional_identities_signature_size" CHECK (signature_file_size IS NULL OR signature_file_size >= 32 AND signature_file_size <= 5242880);
alter table "public"."professional_identities" add constraint "professional_identities_status" CHECK (status = ANY (ARRAY['pending'::text, 'generating'::text, 'active'::text, 'failed'::text]));
alter table "public"."professional_identities" add constraint "professional_identities_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(user_id) ON UPDATE CASCADE ON DELETE CASCADE;
alter table "public"."profiles" add constraint "profiles_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table "public"."profiles" add constraint "profiles_display_name_length" CHECK (char_length(btrim(display_name)) >= 2 AND char_length(btrim(display_name)) <= 80);
alter table "public"."profiles" add constraint "profiles_passport_format" CHECK (passport ~ '^[0-9]{1,4}$'::text);
alter table "public"."profiles" add constraint "profiles_passport_key" UNIQUE (passport);
alter table "public"."profiles" add constraint "profiles_password_reset_by_fkey" FOREIGN KEY (password_reset_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table "public"."profiles" add constraint "profiles_pkey" PRIMARY KEY (id);
alter table "public"."profiles" add constraint "profiles_position_id_fkey" FOREIGN KEY (position_id) REFERENCES staff_positions(id) ON DELETE SET NULL;
alter table "public"."profiles" add constraint "profiles_role_valid" CHECK (role_code = ANY (ARRAY['diretor_geral'::text, 'diretoria'::text, 'funcionario'::text]));
alter table "public"."profiles" add constraint "profiles_status_valid" CHECK (status = ANY (ARRAY['active'::text, 'inactive'::text, 'suspended'::text]));
alter table "public"."profiles" add constraint "profiles_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table "public"."profiles" add constraint "profiles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table "public"."profiles" add constraint "profiles_user_id_key" UNIQUE (user_id);
alter table "public"."recruitment_applications" add constraint "recruitment_applications_discord_id_key" UNIQUE (discord_id);
alter table "public"."recruitment_applications" add constraint "recruitment_applications_passport_key" UNIQUE (passport);
alter table "public"."recruitment_applications" add constraint "recruitment_applications_pkey" PRIMARY KEY (id);
alter table "public"."recruitment_applications" add constraint "recruitment_applications_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table "public"."recruitment_applications" add constraint "recruitment_availability_valid" CHECK (cardinality(availability) >= 1 AND cardinality(availability) <= 4 AND availability <@ ARRAY['morning'::text, 'afternoon'::text, 'evening'::text, 'overnight'::text]);
alter table "public"."recruitment_applications" add constraint "recruitment_birth_day_valid" CHECK (birth_day >= 1 AND birth_day <= 31);
alter table "public"."recruitment_applications" add constraint "recruitment_birth_month_valid" CHECK (birth_month >= 1 AND birth_month <= 12);
alter table "public"."recruitment_applications" add constraint "recruitment_discord_id_format" CHECK (discord_id ~ '^[0-9]{17,20}$'::text);
alter table "public"."recruitment_applications" add constraint "recruitment_experience_summary_length" CHECK (experience_summary IS NULL OR char_length(experience_summary) <= 1000);
alter table "public"."recruitment_applications" add constraint "recruitment_external_calls_valid" CHECK (external_calls = ANY (ARRAY['full'::text, 'partial'::text, 'unavailable'::text]));
alter table "public"."recruitment_applications" add constraint "recruitment_full_name_length" CHECK (char_length(btrim(full_name)) >= 2 AND char_length(btrim(full_name)) <= 100);
alter table "public"."recruitment_applications" add constraint "recruitment_interest_area_valid" CHECK (interest_area = ANY (ARRAY['clinical_care'::text, 'emergency_rescue'::text, 'nursing'::text, 'health_management'::text, 'undecided'::text]));
alter table "public"."recruitment_applications" add constraint "recruitment_motivation_length" CHECK (char_length(btrim(motivation)) >= 30 AND char_length(btrim(motivation)) <= 1200);
alter table "public"."recruitment_applications" add constraint "recruitment_passport_format" CHECK (passport ~ '^[0-9]{1,4}$'::text);
alter table "public"."recruitment_applications" add constraint "recruitment_phone_format" CHECK (city_phone ~ '^\([0-9]{3}\) [0-9]{3}-[0-9]{3}$'::text);
alter table "public"."recruitment_applications" add constraint "recruitment_review_notes_length" CHECK (review_notes IS NULL OR char_length(review_notes) <= 2000);
alter table "public"."recruitment_applications" add constraint "recruitment_status_valid" CHECK (status = ANY (ARRAY['submitted'::text, 'under_review'::text, 'interview'::text, 'approved'::text, 'rejected'::text, 'withdrawn'::text]));
alter table "public"."recruitment_decisions" add constraint "recruitment_decision_reason_valid" CHECK (decision = 'approved'::text AND reason IS NULL OR decision = 'rejected'::text AND char_length(btrim(reason)) >= 10 AND char_length(btrim(reason)) <= 2000);
alter table "public"."recruitment_decisions" add constraint "recruitment_decision_valid" CHECK (decision = ANY (ARRAY['approved'::text, 'rejected'::text]));
alter table "public"."recruitment_decisions" add constraint "recruitment_decisions_application_id_fkey" FOREIGN KEY (application_id) REFERENCES recruitment_applications(id) ON DELETE CASCADE;
alter table "public"."recruitment_decisions" add constraint "recruitment_decisions_decided_by_fkey" FOREIGN KEY (decided_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table "public"."recruitment_decisions" add constraint "recruitment_decisions_pkey" PRIMARY KEY (id);
alter table "public"."rh_absence_requests" add constraint "rh_absence_requests_cancelled_by_fkey" FOREIGN KEY (cancelled_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_absence_requests" add constraint "rh_absence_requests_effect_check" CHECK (approval_effect IS NULL OR (approval_effect = ANY (ARRAY['record_only'::text, 'weekly_exemption'::text, 'weekly_adjustment'::text])));
alter table "public"."rh_absence_requests" add constraint "rh_absence_requests_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_absence_requests" add constraint "rh_absence_requests_observation_check" CHECK (observation IS NULL OR char_length(btrim(observation)) >= 2 AND char_length(btrim(observation)) <= 2000);
alter table "public"."rh_absence_requests" add constraint "rh_absence_requests_period_check" CHECK (end_date >= start_date AND end_date <= (start_date + 89));
alter table "public"."rh_absence_requests" add constraint "rh_absence_requests_pkey" PRIMARY KEY (id);
alter table "public"."rh_absence_requests" add constraint "rh_absence_requests_reason_check" CHECK (char_length(btrim(reason)) >= 10 AND char_length(btrim(reason)) <= 2000);
alter table "public"."rh_absence_requests" add constraint "rh_absence_requests_review_note_check" CHECK (review_note IS NULL OR char_length(btrim(review_note)) >= 2 AND char_length(btrim(review_note)) <= 2000);
alter table "public"."rh_absence_requests" add constraint "rh_absence_requests_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_absence_requests" add constraint "rh_absence_requests_state_check" CHECK (status = 'pending'::text AND approval_effect IS NULL AND reviewed_by IS NULL AND reviewed_at IS NULL AND cancelled_by IS NULL AND cancelled_at IS NULL OR status = 'approved'::text AND approval_effect IS NOT NULL AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL AND cancelled_by IS NULL AND cancelled_at IS NULL OR status = 'rejected'::text AND approval_effect IS NULL AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL AND review_note IS NOT NULL AND cancelled_by IS NULL AND cancelled_at IS NULL OR status = 'cancelled'::text AND approval_effect IS NULL AND reviewed_by IS NULL AND reviewed_at IS NULL AND cancelled_by = employee_id AND cancelled_at IS NOT NULL);
alter table "public"."rh_absence_requests" add constraint "rh_absence_requests_status_check" CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text]));
alter table "public"."rh_disciplinary_reviews" add constraint "rh_disciplinary_reviews_cycle_check" CHECK (cycle_month = date_trunc('month'::text, cycle_month::timestamp with time zone)::date);
alter table "public"."rh_disciplinary_reviews" add constraint "rh_disciplinary_reviews_decided_by_fkey" FOREIGN KEY (decided_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_disciplinary_reviews" add constraint "rh_disciplinary_reviews_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_disciplinary_reviews" add constraint "rh_disciplinary_reviews_note_check" CHECK (decision_note IS NULL OR char_length(btrim(decision_note)) >= 10 AND char_length(btrim(decision_note)) <= 2000);
alter table "public"."rh_disciplinary_reviews" add constraint "rh_disciplinary_reviews_pkey" PRIMARY KEY (id);
alter table "public"."rh_disciplinary_reviews" add constraint "rh_disciplinary_reviews_state_check" CHECK (status = 'pending'::text AND decided_by IS NULL AND decided_at IS NULL AND decision_note IS NULL OR status <> 'pending'::text AND decided_by IS NOT NULL AND decided_at IS NOT NULL AND decision_note IS NOT NULL);
alter table "public"."rh_disciplinary_reviews" add constraint "rh_disciplinary_reviews_status_check" CHECK (status = ANY (ARRAY['pending'::text, 'suspension_maintained'::text, 'dismissed'::text, 'reactivated'::text]));
alter table "public"."rh_disciplinary_reviews" add constraint "rh_disciplinary_reviews_triggered_by_fkey" FOREIGN KEY (triggered_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_disciplinary_reviews" add constraint "rh_disciplinary_reviews_triggered_by_warning_id_fkey" FOREIGN KEY (triggered_by_warning_id) REFERENCES rh_warnings(id) ON DELETE RESTRICT;
alter table "public"."rh_disciplinary_reviews" add constraint "rh_disciplinary_reviews_triggered_by_warning_id_key" UNIQUE (triggered_by_warning_id);
alter table "public"."rh_hour_justifications" add constraint "rh_hour_justifications_credit_check" CHECK (credited_minutes IS NULL OR credited_minutes >= 0 AND credited_minutes <= deficit_minutes);
alter table "public"."rh_hour_justifications" add constraint "rh_hour_justifications_deficit_check" CHECK (deficit_minutes >= 1 AND deficit_minutes <= 60000);
alter table "public"."rh_hour_justifications" add constraint "rh_hour_justifications_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_hour_justifications" add constraint "rh_hour_justifications_note_check" CHECK (review_note IS NULL OR char_length(btrim(review_note)) >= 2 AND char_length(btrim(review_note)) <= 2000);
alter table "public"."rh_hour_justifications" add constraint "rh_hour_justifications_pkey" PRIMARY KEY (id);
alter table "public"."rh_hour_justifications" add constraint "rh_hour_justifications_reason_check" CHECK (char_length(btrim(reason)) >= 10 AND char_length(btrim(reason)) <= 2000);
alter table "public"."rh_hour_justifications" add constraint "rh_hour_justifications_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_hour_justifications" add constraint "rh_hour_justifications_state_check" CHECK (status = 'pending'::text AND credited_minutes IS NULL AND reviewed_by IS NULL AND reviewed_at IS NULL OR status = 'approved'::text AND credited_minutes IS NOT NULL AND credited_minutes > 0 AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL OR status = 'rejected'::text AND credited_minutes = 0 AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL AND review_note IS NOT NULL);
alter table "public"."rh_hour_justifications" add constraint "rh_hour_justifications_status_check" CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text]));
alter table "public"."rh_hour_justifications" add constraint "rh_hour_justifications_weekly_record_id_fkey" FOREIGN KEY (weekly_record_id) REFERENCES rh_weekly_records(id) ON DELETE RESTRICT;
alter table "public"."rh_hour_justifications" add constraint "rh_hour_justifications_weekly_record_id_key" UNIQUE (weekly_record_id);
alter table "public"."rh_hour_snapshots" add constraint "rh_hour_snapshots_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_hour_snapshots" add constraint "rh_hour_snapshots_employee_day_unique" UNIQUE (employee_id, reference_month, reading_date);
alter table "public"."rh_hour_snapshots" add constraint "rh_hour_snapshots_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_hour_snapshots" add constraint "rh_hour_snapshots_note_check" CHECK (note IS NULL OR char_length(note) <= 500);
alter table "public"."rh_hour_snapshots" add constraint "rh_hour_snapshots_pkey" PRIMARY KEY (id);
alter table "public"."rh_hour_snapshots" add constraint "rh_hour_snapshots_reading_month_check" CHECK (reading_date >= reference_month AND reading_date < (reference_month + '1 mon'::interval)::date);
alter table "public"."rh_hour_snapshots" add constraint "rh_hour_snapshots_reference_month_check" CHECK (reference_month = date_trunc('month'::text, reference_month::timestamp with time zone)::date);
alter table "public"."rh_hour_snapshots" add constraint "rh_hour_snapshots_total_check" CHECK (total_minutes >= 0 AND total_minutes <= 60000);
alter table "public"."rh_hour_snapshots" add constraint "rh_hour_snapshots_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_leave_week_adjustments" add constraint "rh_leave_week_adjustments_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_leave_week_adjustments" add constraint "rh_leave_week_adjustments_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_leave_week_adjustments" add constraint "rh_leave_week_adjustments_leave_request_id_fkey" FOREIGN KEY (leave_request_id) REFERENCES rh_absence_requests(id) ON DELETE RESTRICT;
alter table "public"."rh_leave_week_adjustments" add constraint "rh_leave_week_adjustments_minutes_check" CHECK (deducted_minutes >= 1 AND deducted_minutes <= 600);
alter table "public"."rh_leave_week_adjustments" add constraint "rh_leave_week_adjustments_pkey" PRIMARY KEY (id);
alter table "public"."rh_leave_week_adjustments" add constraint "rh_leave_week_adjustments_request_week_unique" UNIQUE (leave_request_id, week_start);
alter table "public"."rh_leave_week_adjustments" add constraint "rh_leave_week_adjustments_week_check" CHECK (EXTRACT(isodow FROM week_start) = 1::numeric);
alter table "public"."rh_warnings" add constraint "rh_warnings_annulled_by_fkey" FOREIGN KEY (annulled_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_warnings" add constraint "rh_warnings_annulment_reason_check" CHECK (annulment_reason IS NULL OR char_length(btrim(annulment_reason)) >= 10 AND char_length(btrim(annulment_reason)) <= 2000);
alter table "public"."rh_warnings" add constraint "rh_warnings_category_check" CHECK (category = ANY (ARRAY['weekly_goal'::text, 'attendance'::text, 'conduct'::text, 'internal_rules'::text, 'other'::text]));
alter table "public"."rh_warnings" add constraint "rh_warnings_cycle_check" CHECK (cycle_month = date_trunc('month'::text, cycle_month::timestamp with time zone)::date);
alter table "public"."rh_warnings" add constraint "rh_warnings_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_warnings" add constraint "rh_warnings_issued_by_fkey" FOREIGN KEY (issued_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_warnings" add constraint "rh_warnings_origin_check" CHECK (origin = ANY (ARRAY['weekly_closure'::text, 'manual'::text]));
alter table "public"."rh_warnings" add constraint "rh_warnings_origin_link_check" CHECK (origin = 'weekly_closure'::text AND weekly_record_id IS NOT NULL OR origin = 'manual'::text AND weekly_record_id IS NULL);
alter table "public"."rh_warnings" add constraint "rh_warnings_pkey" PRIMARY KEY (id);
alter table "public"."rh_warnings" add constraint "rh_warnings_progression_flagged_by_fkey" FOREIGN KEY (progression_flagged_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_warnings" add constraint "rh_warnings_progression_note_check" CHECK (progression_impact_note IS NULL OR char_length(btrim(progression_impact_note)) >= 2 AND char_length(btrim(progression_impact_note)) <= 1000);
alter table "public"."rh_warnings" add constraint "rh_warnings_progression_state_check" CHECK (NOT impacts_progression AND progression_flagged_by IS NULL AND progression_flagged_at IS NULL AND progression_impact_note IS NULL OR impacts_progression AND progression_flagged_by IS NOT NULL AND progression_flagged_at IS NOT NULL);
alter table "public"."rh_warnings" add constraint "rh_warnings_reason_check" CHECK (char_length(btrim(reason)) >= 10 AND char_length(btrim(reason)) <= 1000);
alter table "public"."rh_warnings" add constraint "rh_warnings_sequence_check" CHECK (sequence_in_cycle >= 1 AND sequence_in_cycle <= 3);
alter table "public"."rh_warnings" add constraint "rh_warnings_state_check" CHECK (status = 'active'::text AND annulled_by IS NULL AND annulled_at IS NULL AND annulment_reason IS NULL OR status = 'annulled'::text AND annulled_by IS NOT NULL AND annulled_at IS NOT NULL AND annulment_reason IS NOT NULL);
alter table "public"."rh_warnings" add constraint "rh_warnings_status_check" CHECK (status = ANY (ARRAY['active'::text, 'annulled'::text]));
alter table "public"."rh_warnings" add constraint "rh_warnings_weekly_record_id_fkey" FOREIGN KEY (weekly_record_id) REFERENCES rh_weekly_records(id) ON DELETE RESTRICT;
alter table "public"."rh_warnings" add constraint "rh_warnings_weekly_record_id_key" UNIQUE (weekly_record_id);
alter table "public"."rh_week_closures" add constraint "rh_week_closures_closed_by_fkey" FOREIGN KEY (closed_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_week_closures" add constraint "rh_week_closures_pkey" PRIMARY KEY (id);
alter table "public"."rh_week_closures" add constraint "rh_week_closures_started_by_fkey" FOREIGN KEY (started_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_week_closures" add constraint "rh_week_closures_state_check" CHECK ((status = ANY (ARRAY['open'::text, 'reopened'::text])) OR status = 'closed'::text AND closed_by IS NOT NULL AND closed_at IS NOT NULL);
alter table "public"."rh_week_closures" add constraint "rh_week_closures_status_check" CHECK (status = ANY (ARRAY['open'::text, 'closed'::text, 'reopened'::text]));
alter table "public"."rh_week_closures" add constraint "rh_week_closures_week_check" CHECK (EXTRACT(isodow FROM week_start) = 1::numeric AND week_end = (week_start + 6));
alter table "public"."rh_week_closures" add constraint "rh_week_closures_week_start_key" UNIQUE (week_start);
alter table "public"."rh_week_reopen_events" add constraint "rh_week_reopen_events_closure_id_fkey" FOREIGN KEY (closure_id) REFERENCES rh_week_closures(id) ON DELETE RESTRICT;
alter table "public"."rh_week_reopen_events" add constraint "rh_week_reopen_events_pkey" PRIMARY KEY (id);
alter table "public"."rh_week_reopen_events" add constraint "rh_week_reopen_events_reason_check" CHECK (char_length(btrim(reason)) >= 10 AND char_length(btrim(reason)) <= 2000);
alter table "public"."rh_week_reopen_events" add constraint "rh_week_reopen_events_reopened_by_fkey" FOREIGN KEY (reopened_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_absence_request_id_fkey" FOREIGN KEY (absence_request_id) REFERENCES rh_absence_requests(id) ON DELETE RESTRICT;
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_base_required_check" CHECK (base_required_minutes >= 0 AND base_required_minutes <= 60000);
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_calculation_check" CHECK (required_minutes = GREATEST(0, base_required_minutes - leave_deduction_minutes) AND deficit_minutes = GREATEST(0, required_minutes - worked_minutes) AND remaining_deficit_minutes = GREATEST(0, deficit_minutes - justification_minutes));
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_closed_by_fkey" FOREIGN KEY (closed_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_closure_id_fkey" FOREIGN KEY (closure_id) REFERENCES rh_week_closures(id) ON DELETE RESTRICT;
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_closure_status_check" CHECK (closure_status = ANY (ARRAY['awaiting_justification'::text, 'justification_pending'::text, 'ready'::text, 'closed'::text]));
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_cycle_check" CHECK (cycle_month = date_trunc('month'::text, week_end::timestamp with time zone)::date);
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_deficit_check" CHECK (deficit_minutes >= 0 AND deficit_minutes <= 60000);
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_employee_week_unique" UNIQUE (employee_id, week_start);
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_justification_minutes_check" CHECK (justification_minutes >= 0 AND justification_minutes <= deficit_minutes);
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_leave_deduction_check" CHECK (leave_deduction_minutes >= 0 AND leave_deduction_minutes <= base_required_minutes);
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_note_check" CHECK (closure_note IS NULL OR char_length(closure_note) <= 1000);
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_pkey" PRIMARY KEY (id);
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_remaining_deficit_check" CHECK (remaining_deficit_minutes >= 0 AND remaining_deficit_minutes <= deficit_minutes);
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_required_check" CHECK (required_minutes >= 0 AND required_minutes <= 60000);
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_status_check" CHECK (status = ANY (ARRAY['met'::text, 'justified'::text, 'deficit'::text, 'warning_issued'::text, 'warning_annulled'::text]));
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_week_check" CHECK (EXTRACT(isodow FROM week_start) = 1::numeric AND week_end = (week_start + 6));
alter table "public"."rh_weekly_records" add constraint "rh_weekly_records_worked_check" CHECK (worked_minutes >= 0 AND worked_minutes <= 60000);
alter table "public"."service_catalog" add constraint "service_catalog_category_check" CHECK (char_length(btrim(category)) >= 2 AND char_length(btrim(category)) <= 60);
alter table "public"."service_catalog" add constraint "service_catalog_code_check" CHECK (code ~ '^[a-z0-9_]{2,48}$'::text);
alter table "public"."service_catalog" add constraint "service_catalog_code_unique" UNIQUE (code);
alter table "public"."service_catalog" add constraint "service_catalog_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table "public"."service_catalog" add constraint "service_catalog_icon_check" CHECK (char_length(icon) >= 1 AND char_length(icon) <= 12);
alter table "public"."service_catalog" add constraint "service_catalog_image_path_check" CHECK (image_path IS NULL OR image_path ~ '^items/[0-9]+/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'::text);
alter table "public"."service_catalog" add constraint "service_catalog_name_check" CHECK (char_length(btrim(name)) >= 2 AND char_length(btrim(name)) <= 100);
alter table "public"."service_catalog" add constraint "service_catalog_pkey" PRIMARY KEY (id);
alter table "public"."service_catalog" add constraint "service_catalog_sort_order_check" CHECK (sort_order >= '-10000'::integer AND sort_order <= 10000);
alter table "public"."service_catalog" add constraint "service_catalog_unit_price_check" CHECK (unit_price >= 0::numeric);
alter table "public"."service_catalog" add constraint "service_catalog_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table "public"."staff_course_records" add constraint "staff_course_records_assigned_by_fkey" FOREIGN KEY (assigned_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."staff_course_records" add constraint "staff_course_records_completed_by_fkey" FOREIGN KEY (completed_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."staff_course_records" add constraint "staff_course_records_completion_check" CHECK (status = 'pending'::text AND completed_by IS NULL AND completed_at IS NULL OR status = 'completed'::text AND completed_by IS NOT NULL AND completed_at IS NOT NULL);
alter table "public"."staff_course_records" add constraint "staff_course_records_course_id_fkey" FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE RESTRICT;
alter table "public"."staff_course_records" add constraint "staff_course_records_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."staff_course_records" add constraint "staff_course_records_pkey" PRIMARY KEY (id);
alter table "public"."staff_course_records" add constraint "staff_course_records_status_check" CHECK (status = ANY (ARRAY['pending'::text, 'completed'::text]));
alter table "public"."staff_course_records" add constraint "staff_course_records_unique" UNIQUE (course_id, employee_id);
alter table "public"."staff_position_history" add constraint "staff_position_history_change_check" CHECK (from_position_id IS NULL OR from_position_id <> to_position_id);
alter table "public"."staff_position_history" add constraint "staff_position_history_decided_by_fkey" FOREIGN KEY (decided_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."staff_position_history" add constraint "staff_position_history_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."staff_position_history" add constraint "staff_position_history_event_check" CHECK (event_type = ANY (ARRAY['initial_assignment'::text, 'promotion'::text, 'appointment'::text, 'succession'::text, 'override'::text]));
alter table "public"."staff_position_history" add constraint "staff_position_history_from_position_id_fkey" FOREIGN KEY (from_position_id) REFERENCES staff_positions(id) ON DELETE RESTRICT;
alter table "public"."staff_position_history" add constraint "staff_position_history_note_check" CHECK (note IS NULL OR char_length(btrim(note)) >= 2 AND char_length(btrim(note)) <= 2000);
alter table "public"."staff_position_history" add constraint "staff_position_history_pkey" PRIMARY KEY (id);
alter table "public"."staff_position_history" add constraint "staff_position_history_to_position_id_fkey" FOREIGN KEY (to_position_id) REFERENCES staff_positions(id) ON DELETE RESTRICT;
alter table "public"."staff_position_permissions" add constraint "staff_position_permissions_granted_by_fkey" FOREIGN KEY (granted_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."staff_position_permissions" add constraint "staff_position_permissions_permission_code_fkey" FOREIGN KEY (permission_code) REFERENCES system_permissions(code) ON DELETE RESTRICT;
alter table "public"."staff_position_permissions" add constraint "staff_position_permissions_pkey" PRIMARY KEY (position_id, permission_code);
alter table "public"."staff_position_permissions" add constraint "staff_position_permissions_position_id_fkey" FOREIGN KEY (position_id) REFERENCES staff_positions(id) ON DELETE CASCADE;
alter table "public"."staff_position_transition_rules" add constraint "staff_position_transition_rules_from_position_id_fkey" FOREIGN KEY (from_position_id) REFERENCES staff_positions(id) ON DELETE RESTRICT;
alter table "public"."staff_position_transition_rules" add constraint "staff_position_transition_rules_minimums_check" CHECK (min_days >= 0 AND min_days <= 3650 AND min_worked_minutes >= 0 AND min_worked_minutes <= 1000000 AND min_attendances >= 0 AND min_attendances <= 10000);
alter table "public"."staff_position_transition_rules" add constraint "staff_position_transition_rules_pkey" PRIMARY KEY (id);
alter table "public"."staff_position_transition_rules" add constraint "staff_position_transition_rules_to_position_id_fkey" FOREIGN KEY (to_position_id) REFERENCES staff_positions(id) ON DELETE RESTRICT;
alter table "public"."staff_position_transition_rules" add constraint "staff_position_transition_rules_type_check" CHECK (transition_type = ANY (ARRAY['progression'::text, 'appointment'::text, 'succession'::text]));
alter table "public"."staff_position_transition_rules" add constraint "staff_position_transition_rules_unique" UNIQUE (from_position_id, to_position_id);
alter table "public"."staff_position_transition_rules" add constraint "staff_position_transition_rules_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."staff_positions" add constraint "staff_positions_advancement_mode_check" CHECK (advancement_mode = ANY (ARRAY['progression'::text, 'appointment'::text, 'succession'::text]));
alter table "public"."staff_positions" add constraint "staff_positions_code_check" CHECK (code ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'::text);
alter table "public"."staff_positions" add constraint "staff_positions_code_key" UNIQUE (code);
alter table "public"."staff_positions" add constraint "staff_positions_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."staff_positions" add constraint "staff_positions_level_check" CHECK (level >= 1 AND level <= 14);
alter table "public"."staff_positions" add constraint "staff_positions_name_check" CHECK (char_length(btrim(name)) >= 2 AND char_length(btrim(name)) <= 80);
alter table "public"."staff_positions" add constraint "staff_positions_name_key" UNIQUE (name);
alter table "public"."staff_positions" add constraint "staff_positions_pkey" PRIMARY KEY (id);
alter table "public"."staff_positions" add constraint "staff_positions_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."staff_promotion_reviews" add constraint "staff_promotion_reviews_decided_by_fkey" FOREIGN KEY (decided_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."staff_promotion_reviews" add constraint "staff_promotion_reviews_decision_check" CHECK (status = 'pending'::text AND decided_by IS NULL AND decided_at IS NULL AND decision_note IS NULL OR status <> 'pending'::text AND decided_by IS NOT NULL AND decided_at IS NOT NULL);
alter table "public"."staff_promotion_reviews" add constraint "staff_promotion_reviews_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."staff_promotion_reviews" add constraint "staff_promotion_reviews_from_position_id_fkey" FOREIGN KEY (from_position_id) REFERENCES staff_positions(id) ON DELETE RESTRICT;
alter table "public"."staff_promotion_reviews" add constraint "staff_promotion_reviews_metrics_check" CHECK (required_days >= 0 AND elapsed_days >= 0 AND worked_minutes >= 0 AND attendance_count >= 0 AND flagged_warning_count >= 0);
alter table "public"."staff_promotion_reviews" add constraint "staff_promotion_reviews_note_check" CHECK (decision_note IS NULL OR char_length(btrim(decision_note)) >= 2 AND char_length(btrim(decision_note)) <= 2000);
alter table "public"."staff_promotion_reviews" add constraint "staff_promotion_reviews_pkey" PRIMARY KEY (id);
alter table "public"."staff_promotion_reviews" add constraint "staff_promotion_reviews_status_check" CHECK (status = ANY (ARRAY['pending'::text, 'promoted'::text, 'deferred'::text, 'cancelled'::text]));
alter table "public"."staff_promotion_reviews" add constraint "staff_promotion_reviews_to_position_id_fkey" FOREIGN KEY (to_position_id) REFERENCES staff_positions(id) ON DELETE RESTRICT;
alter table "public"."system_permissions" add constraint "system_permissions_code_check" CHECK (code ~ '^[a-z0-9]+(?:\.[a-z0-9]+)*$'::text);
alter table "public"."system_permissions" add constraint "system_permissions_label_check" CHECK (char_length(btrim(label)) >= 2 AND char_length(btrim(label)) <= 100);
alter table "public"."system_permissions" add constraint "system_permissions_module_check" CHECK (char_length(btrim(module)) >= 2 AND char_length(btrim(module)) <= 40);
alter table "public"."system_permissions" add constraint "system_permissions_pkey" PRIMARY KEY (code);
alter table "public"."system_settings" add constraint "system_settings_pkey" PRIMARY KEY (key);
alter table "public"."user_permission_grants" add constraint "user_permission_grants_granted_by_fkey" FOREIGN KEY (granted_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."user_permission_grants" add constraint "user_permission_grants_kind_check" CHECK (grant_kind = ANY (ARRAY['individual'::text, 'temporary'::text]));
alter table "public"."user_permission_grants" add constraint "user_permission_grants_permission_code_fkey" FOREIGN KEY (permission_code) REFERENCES system_permissions(code) ON DELETE RESTRICT;
alter table "public"."user_permission_grants" add constraint "user_permission_grants_pkey" PRIMARY KEY (id);
alter table "public"."user_permission_grants" add constraint "user_permission_grants_reason_check" CHECK (reason IS NULL OR char_length(btrim(reason)) >= 2 AND char_length(btrim(reason)) <= 1000);
alter table "public"."user_permission_grants" add constraint "user_permission_grants_revocation_check" CHECK (revoked_at IS NULL AND revoked_by IS NULL AND revoked_reason IS NULL OR revoked_at IS NOT NULL AND revoked_by IS NOT NULL AND char_length(btrim(revoked_reason)) >= 10 AND char_length(btrim(revoked_reason)) <= 1000);
alter table "public"."user_permission_grants" add constraint "user_permission_grants_revoked_by_fkey" FOREIGN KEY (revoked_by) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."user_permission_grants" add constraint "user_permission_grants_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(user_id) ON DELETE RESTRICT;
alter table "public"."user_permission_grants" add constraint "user_permission_grants_window_check" CHECK (grant_kind = 'individual'::text AND expires_at IS NULL OR grant_kind = 'temporary'::text AND expires_at IS NOT NULL AND expires_at > valid_from);

-- Comentários estruturais.
comment on column "public"."attendance_items"."discount_percent" is 'Percentual automático do plano preservado no momento do atendimento.';
comment on table "public"."attendance_items" is 'Itens imutáveis do atendimento, com nome e valor preservados no momento do registro.';
comment on column "public"."attendances"."patient_id" is 'Paciente vinculado ao atendimento; nulo somente para venda avulsa restrita a insumos e medicamentos.';
comment on column "public"."attendances"."plan_name" is 'Nome do plano preservado no momento do atendimento.';
comment on table "public"."attendances" is 'Atendimentos financeiros do hospital; não contém prontuário clínico.';
comment on table "public"."audit_logs" is 'Histórico somente leitura para usuários; mutações são feitas por gatilhos.';
comment on table "public"."benefit_plans" is 'Três planos fixos disponíveis para vínculo ao cadastro do paciente.';
comment on table "public"."clinical_exam_document_shares" is 'Tokens públicos aleatórios e revogáveis para o PNG canônico do exame concluído.';
comment on table "public"."clinical_exam_documents" is 'Metadados do PNG canônico imutável gerado a partir do snapshot final aprovado.';
comment on column "public"."clinical_exam_images"."source" is 'Origem da imagem: upload manual nesta fase; ai_generated reservado para evolução futura.';
comment on table "public"."clinical_exam_images" is 'Metadados protegidos das imagens clínicas; os bytes permanecem no bucket privado clinical-exam-images.';
comment on table "public"."clinical_exam_report_versions" is 'Snapshots imutáveis de cada envio do laudo para revisão e sua decisão.';
comment on table "public"."clinical_exam_status_history" is 'Histórico funcional imutável das transições do exame clínico.';
comment on column "public"."clinical_exams"."attendance_id" is 'Vínculo opcional e explícito com atendimento financeiro real do mesmo paciente.';
comment on column "public"."clinical_exams"."result_data" is 'Resultado clínico com snapshot imutável do template para laboratórios e exames de imagem.';
comment on column "public"."clinical_exams"."final_report_snapshot" is 'Snapshot final do laudo efetivamente aprovado, preservando conteúdo, autoria e contexto clínico.';
comment on table "public"."clinical_exams" is 'Exames clínicos manuais; não são criados automaticamente por vendas.';
comment on table "public"."courses" is 'Catálogo flexível de cursos do RP; cursos com histórico são inativados, não apagados.';
comment on table "public"."dashboard_preferences" is 'Preferência pessoal de layout, widgets ocultos e atalhos do Dashboard; não armazena conteúdo operacional.';
comment on column "public"."exam_ai_generations"."draft_storage_path" is 'Path privado temporário; nunca contém dados pessoais nem signed URL.';
comment on column "public"."exam_ai_generations"."source_image_generation_id" is 'Rascunho privado efetivamente analisado pela Luna, quando aplicável.';
comment on column "public"."exam_ai_generations"."source_image_id" is 'Imagem clínica oficial efetivamente analisada pela Luna, quando aplicável.';
comment on table "public"."exam_ai_generations" is 'Gerações assistivas de IA da Fase 4.6; sugestões exigem decisão humana explícita.';
comment on table "public"."exam_categories" is 'Categorias configuráveis da Central de Exames; histórico é preservado por inativação.';
comment on column "public"."exam_types"."result_config" is 'Template configurável e versionado; laboratórios usam hpsm.lab_template.v1 e imagens usam hpsm.image_template.v1.';
comment on table "public"."exam_types" is 'Tipos clínicos configuráveis, independentes do catálogo financeiro.';
comment on table "public"."notification_reads" is 'Confirmacoes individuais de leitura das notificacoes visiveis para cada usuario.';
comment on table "public"."notifications" is 'Notificacoes pessoais, alertas de fluxo e avisos institucionais do mural interno.';
comment on table "public"."partnership_pending_beneficiaries" is 'Pessoas informadas por passaporte que ainda aguardam cadastro ou revisão interna.';
comment on table "public"."partnerships" is 'Organizações conveniadas ao HPSM; inativação preserva vínculos e histórico.';
comment on table "public"."patient_health_plan_requests" is 'Solicitações idempotentes de ativação ou renovação do Plano de Saúde HPSM originadas por vendas concluídas.';
comment on table "public"."patient_partnerships" is 'Vínculos temporais entre pacientes canônicos e parcerias.';
comment on column "public"."patients"."passport" is 'Passaporte único do paciente, preservado como texto para manter zeros à esquerda.';
comment on column "public"."patients"."phone" is 'Telefone principal no formato obrigatório (055) 123-456.';
comment on column "public"."patients"."emergency_contact_name" is 'Nome opcional do contato de emergência; deve ser informado junto com o telefone.';
comment on column "public"."patients"."emergency_contact_phone" is 'Telefone opcional do contato de emergência no formato (055) 123-456; deve ser informado junto com o nome.';
comment on column "public"."patients"."plan_code" is 'Plano ativo atual do paciente. Nulo indica que o paciente não possui plano ativo.';
comment on column "public"."patients"."birth_date" is 'Data de nascimento canônica do paciente. Nullable apenas para cadastros históricos anteriores à Fase 6.1.';
comment on table "public"."patients" is 'Cadastro administrativo de pacientes, sem identidade de acesso ao sistema.';
comment on table "public"."plan_discounts" is 'Percentual de desconto definido pela Diretoria para cada combinação de plano e item.';
comment on column "public"."professional_identities"."crm_code" is 'Passaporte com quatro digitos seguido de DDMM da admissao; alteravel somente por correcao auditada do Diretor Geral.';
comment on column "public"."professional_identities"."registration_date" is 'Data canonica de admissao usada na composicao do CRM interno.';
comment on column "public"."professional_identities"."identity_locked" is 'Bloqueio institucional; somente o fluxo administrativo do Diretor Geral pode abrir reprocessamento.';
comment on table "public"."professional_identities" is 'Identidade institucional de todos os profissionais HPSM: CRM interno, assinatura e rubrica privadas.';
comment on column "public"."profiles"."passport" is 'Passaporte único do usuário/profissional, preservado como texto para manter zeros à esquerda.';
comment on table "public"."recruitment_applications" is 'Candidaturas externas ao corpo clinico. Dados reais ficam limitados ao ID do Discord.';
comment on table "public"."recruitment_decisions" is 'Histórico imutável das aprovações e recusas registradas pela Diretoria.';
comment on table "public"."rh_absence_requests" is 'Afastamentos preventivos solicitados antes da ausência e analisados pela Diretoria.';
comment on table "public"."rh_disciplinary_reviews" is 'Análises abertas automaticamente quando o colaborador atinge três advertências ativas no mês.';
comment on table "public"."rh_hour_justifications" is 'Justificativas reativas enviadas após a apuração de um déficit semanal.';
comment on table "public"."rh_hour_snapshots" is 'Leituras manuais do acumulado mensal de horas informado pelo sistema da cidade.';
comment on table "public"."rh_leave_week_adjustments" is 'Horas abatidas da meta em cada semana afetada por um afastamento aprovado.';
comment on table "public"."rh_warnings" is 'Advertências manuais ou decorrentes de déficit, contabilizadas no ciclo mensal.';
comment on table "public"."rh_week_closures" is 'Controle humano do fechamento coletivo de cada semana de segunda a domingo.';
comment on table "public"."rh_week_reopen_events" is 'Histórico imutável das reaberturas de semanas e suas fundamentações.';
comment on table "public"."rh_weekly_records" is 'Apurações semanais com meta original, abatimentos, justificativas e déficit restante.';
comment on table "public"."service_catalog" is 'Catálogo fixo de 22 produtos e procedimentos; somente preços podem ser ajustados pela Diretoria.';
comment on table "public"."staff_course_records" is 'Vínculos pendentes ou concluídos entre curso e colaborador.';
comment on table "public"."staff_position_history" is 'Histórico permanente de cargo, promoções, nomeações e sucessões.';
comment on table "public"."staff_position_permissions" is 'Permissões permanentes herdadas pelo cargo ativo do profissional.';
comment on table "public"."staff_positions" is 'Cargos organizacionais da equipe, independentes do nível de acesso legado.';
comment on table "public"."staff_promotion_reviews" is 'Pendências de promoção criadas quando os requisitos mínimos são atendidos; nunca promove automaticamente.';
comment on table "public"."system_permissions" is 'Catálogo fechado de capacidades administrativas do HPSM.';
comment on table "public"."user_permission_grants" is 'Exceções individuais permanentes ou temporárias, com validade, revogação e auditoria.';

-- Views e materialized views.
create or replace view "public"."patient_directory" as
 SELECT patient.id,
    patient.passport,
    patient.name,
    patient.phone,
    patient.emergency_contact_name,
    patient.emergency_contact_phone,
    patient.created_at,
    patient.updated_at,
    last_attendance.created_at AS last_attendance_at,
        CASE
            WHEN approved.coverage_end > now() THEN 'active'::text
            WHEN approved.id IS NOT NULL THEN 'expired'::text
            WHEN pending.id IS NOT NULL THEN 'awaiting_confirmation'::text
            ELSE 'none'::text
        END AS plan_status,
    approved.coverage_start AS plan_activated_at,
    approved.coverage_end AS plan_valid_until,
    approved.reviewed_by AS plan_authorized_by,
    reviewer.display_name AS plan_authorized_by_name,
    pending.id AS pending_request_id,
    pending.requested_at AS pending_requested_at,
    patient.birth_date
   FROM patients patient
     LEFT JOIN LATERAL ( SELECT attendance.created_at
           FROM attendances attendance
          WHERE attendance.patient_id = patient.id AND attendance.status = 'completed'::text
          ORDER BY attendance.created_at DESC, attendance.id DESC
         LIMIT 1) last_attendance ON true
     LEFT JOIN LATERAL ( SELECT request.id,
            request.coverage_start,
            request.coverage_end,
            request.reviewed_by
           FROM patient_health_plan_requests request
          WHERE request.patient_id = patient.id AND request.status = 'approved'::text
          ORDER BY request.coverage_end DESC, request.id DESC
         LIMIT 1) approved ON true
     LEFT JOIN profiles reviewer ON reviewer.user_id = approved.reviewed_by
     LEFT JOIN LATERAL ( SELECT request.id,
            request.requested_at
           FROM patient_health_plan_requests request
          WHERE request.patient_id = patient.id AND request.status = 'pending'::text
          ORDER BY request.requested_at, request.id
         LIMIT 1) pending ON true;;

-- Funções públicas e privadas.
CREATE OR REPLACE FUNCTION private.assert_valid_image_template(p_config jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if p_config is null
     or jsonb_typeof(p_config) <> 'object'
     or p_config->>'schema' <> 'hpsm.image_template.v1'
     or p_config->>'kind' <> 'imaging'
     or coalesce((p_config->>'version') ~ '^[1-9][0-9]*$', false) is not true
     or jsonb_typeof(p_config->'region') <> 'object'
     or jsonb_typeof(p_config#>'{region,required}') <> 'boolean'
     or jsonb_typeof(p_config#>'{region,options}') <> 'array'
     or jsonb_array_length(p_config#>'{region,options}') not between 1 and 60
     or jsonb_typeof(p_config->'supports_laterality') <> 'boolean'
     or jsonb_typeof(p_config->'supports_contrast') <> 'boolean'
     or jsonb_typeof(p_config->'requires_image') <> 'boolean'
     or jsonb_typeof(p_config->'allows_multiple_images') <> 'boolean' then
    raise exception 'Template de imagem inválido.';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_config#>'{region,options}') option_value
    where jsonb_typeof(option_value) <> 'string'
       or char_length(btrim(option_value #>> '{}')) not between 2 and 120
  ) or (
    select count(*) <> count(distinct lower(btrim(option_value #>> '{}')))
    from jsonb_array_elements(p_config#>'{region,options}') option_value
  ) then
    raise exception 'Revise as regiões disponíveis no template.';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION private.assert_valid_lab_template(p_config jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if p_config is null
     or jsonb_typeof(p_config) <> 'object'
     or p_config->>'schema' <> 'hpsm.lab_template.v1'
     or p_config->>'kind' <> 'laboratory'
     or coalesce((p_config->>'version') ~ '^[1-9][0-9]*$', false) is not true
     or jsonb_typeof(p_config->'parameters') <> 'array' then
    raise exception 'Template laboratorial inválido.';
  end if;

  if jsonb_array_length(p_config->'parameters') > 100 then
    raise exception 'O template pode conter no máximo 100 parâmetros.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_config->'parameters') parameter
    where jsonb_typeof(parameter) <> 'object'
       or coalesce(parameter->>'key', '') !~ '^[a-z0-9_]{2,64}$'
       or char_length(btrim(coalesce(parameter->>'label', ''))) not between 2 and 100
       or coalesce(parameter->>'field_type', '') not in ('number', 'text', 'select', 'observation', 'percent')
       or char_length(coalesce(parameter->>'unit', '')) > 40
       or char_length(coalesce(parameter->>'reference', '')) > 240
       or jsonb_typeof(parameter->'required') <> 'boolean'
       or jsonb_typeof(parameter->'active') <> 'boolean'
       or coalesce((parameter->>'sort_order') ~ '^-?[0-9]+$', false) is not true
       or (parameter->>'field_type' = 'select' and (
         jsonb_typeof(parameter->'options') <> 'array'
         or jsonb_array_length(parameter->'options') not between 2 and 50
         or exists (
           select 1 from jsonb_array_elements(parameter->'options') option_value
           where jsonb_typeof(option_value) <> 'string'
              or char_length(btrim(option_value #>> '{}')) not between 1 and 80
         )
       ))
  ) then
    raise exception 'Revise os campos, tipos e opções dos parâmetros do template.';
  end if;

  if (
    select count(*) <> count(distinct parameter->>'key')
    from jsonb_array_elements(p_config->'parameters') parameter
  ) then
    raise exception 'Cada parâmetro deve possuir um identificador único.';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION private.assign_current_exam_ai_prompt_version()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.prompt_version := case new.generation_type
    when 'generate_image' then 'exam-image-clinical-v3'
    when 'generate_lab_results' then 'exam-clinical-lab-v3'
    when 'generate_report' then 'exam-clinical-report-v4'
    when 'generate_exam' then 'exam-clinical-exam-v5'
    else new.prompt_version
  end;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.attach_clinical_exam_report_context(p_exam_type_id bigint, p_result_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_type_snapshot jsonb;
begin
  select jsonb_build_object(
    'id', exam_type.id,
    'code', exam_type.code,
    'name', exam_type.name,
    'category_id', category.id,
    'category_code', category.code,
    'category_name', category.name,
    'result_config', exam_type.result_config
  )
  into v_type_snapshot
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = p_exam_type_id;

  if v_type_snapshot is null then
    raise exception 'Tipo de exame não localizado.';
  end if;

  return coalesce(p_result_data, '{}'::jsonb) || jsonb_build_object(
    'report_config_snapshot', private.clinical_exam_report_config(p_exam_type_id),
    'exam_type_snapshot', v_type_snapshot
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.audit_cast_action(p_actor_id uuid, p_action text, p_cast_id bigint, p_old_values jsonb, p_new_values jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_passport text;
begin
  if p_actor_id is null then
    raise exception 'Ação sem profissional autenticado.';
  end if;
  select profile.passport into v_passport
  from public.profiles profile
  where profile.user_id = p_actor_id and profile.status = 'active';
  if v_passport is null then
    raise exception 'Profissional não autorizado.';
  end if;
  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
  ) values (
    p_actor_id, v_passport, p_action, 'clinical_casts', p_cast_id::text, p_old_values, p_new_values
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.audit_exam_action(p_actor_id uuid, p_action text, p_entity_name text, p_entity_id text, p_old_values jsonb, p_new_values jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_passport text;
begin
  if p_actor_id is null then
    raise exception 'Ação sem profissional autenticado.';
  end if;
  select profile.passport into v_passport
  from public.profiles profile
  where profile.user_id = p_actor_id and profile.status = 'active';
  if v_passport is null then
    raise exception 'Profissional não autorizado.';
  end if;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (p_actor_id, v_passport, p_action, p_entity_name, p_entity_id, p_old_values, p_new_values);
end;
$function$;

CREATE OR REPLACE FUNCTION private.audit_patient_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid;
  v_actor_passport text;
  v_old_values jsonb;
  v_new_values jsonb;
begin
  v_actor_id := coalesce(
    (select auth.uid()),
    case when tg_op = 'DELETE' then old.updated_by else new.updated_by end,
    case when tg_op = 'DELETE' then old.created_by else new.created_by end
  );

  if v_actor_id is not null then
    select profile.passport
    into v_actor_passport
    from public.profiles profile
    where profile.user_id = v_actor_id;
  end if;

  if tg_op in ('UPDATE', 'DELETE') then
    v_old_values := to_jsonb(old) - 'birth_date';
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    v_new_values := to_jsonb(new) - 'birth_date';
  end if;

  if tg_op = 'INSERT' then
    v_new_values := v_new_values || jsonb_build_object('birth_date_present', new.birth_date is not null);
  elsif tg_op = 'UPDATE' and new.birth_date is distinct from old.birth_date then
    v_old_values := v_old_values || jsonb_build_object('birth_date_changed', true);
    v_new_values := v_new_values || jsonb_build_object('birth_date_changed', true);
  end if;

  insert into public.audit_logs (
    actor_user_id,
    actor_passport,
    action,
    entity_name,
    entity_id,
    old_values,
    new_values
  ) values (
    v_actor_id,
    v_actor_passport,
    tg_op,
    tg_table_name,
    coalesce(case when tg_op = 'DELETE' then old.id else new.id end, 0)::text,
    v_old_values,
    v_new_values
  );

  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

CREATE OR REPLACE FUNCTION private.audit_row_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_id uuid;
  actor_code text;
  row_id text;
  row_values jsonb;
begin
  actor_id := auth.uid();
  row_values := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  if actor_id is null then
    actor_id := coalesce(
      nullif(row_values ->> 'updated_by', '')::uuid,
      nullif(row_values ->> 'reviewed_by', '')::uuid,
      nullif(row_values ->> 'cancelled_by', '')::uuid,
      nullif(row_values ->> 'annulled_by', '')::uuid,
      nullif(row_values ->> 'decided_by', '')::uuid,
      nullif(row_values ->> 'voted_by', '')::uuid,
      nullif(row_values ->> 'completed_by', '')::uuid,
      nullif(row_values ->> 'assigned_by', '')::uuid,
      nullif(row_values ->> 'closed_by', '')::uuid,
      nullif(row_values ->> 'issued_by', '')::uuid,
      nullif(row_values ->> 'triggered_by', '')::uuid,
      nullif(row_values ->> 'approved_by', '')::uuid,
      nullif(row_values ->> 'started_by', '')::uuid,
      nullif(row_values ->> 'reopened_by', '')::uuid,
      nullif(row_values ->> 'revoked_by', '')::uuid,
      nullif(row_values ->> 'granted_by', '')::uuid,
      nullif(row_values ->> 'created_by', '')::uuid,
      nullif(row_values ->> 'performed_by', '')::uuid,
      nullif(row_values ->> 'password_reset_by', '')::uuid,
      nullif(row_values ->> 'employee_id', '')::uuid
    );
  end if;
  select passport into actor_code from public.profiles where user_id = actor_id;
  row_id := coalesce(
    row_values ->> 'id', row_values ->> 'key', row_values ->> 'user_id',
    concat_ws(':', row_values ->> 'position_id', row_values ->> 'permission_code')
  );
  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
  ) values (
    actor_id, actor_code, tg_op, tg_table_name, row_id,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

CREATE OR REPLACE FUNCTION private.build_clinical_exam_report_snapshot(p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'schema', 'hpsm.exam_report_snapshot.v1',
    'exam', coalesce(exam.result_data->'exam_type_snapshot', jsonb_build_object(
      'id', exam_type.id, 'code', exam_type.code, 'name', exam_type.name,
      'category_id', category.id, 'category_code', category.code, 'category_name', category.name,
      'result_config', exam_type.result_config
    )),
    'patient', jsonb_build_object('id', patient.id, 'name', patient.name, 'passport', patient.passport),
    'indication', exam.indication,
    'clinical_context', exam.clinical_context,
    'report_config', coalesce(exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(exam.exam_type_id)),
    'content', jsonb_build_object(
      'technique', exam.technique, 'findings', exam.findings, 'conclusion', exam.conclusion,
      'observations', nullif(exam.result_data->>'notes', ''),
      'result_data', exam.result_data - 'report_config_snapshot' - 'exam_type_snapshot'
    ),
    'images', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', image.id, 'caption', image.caption, 'mime_type', image.mime_type,
        'original_filename', image.original_filename, 'sort_order', image.sort_order,
        'source', image.source, 'uploaded_by', image.uploaded_by, 'created_at', image.created_at
      ) order by image.sort_order, image.created_at, image.id)
      from public.clinical_exam_images image
      where image.exam_id = exam.id and image.removed_at is null
    ), '[]'::jsonb),
    'requested_by', jsonb_build_object(
      'id', requester.user_id, 'name', requester.display_name, 'position', requester_position.name,
      'identity', case when requester_identity.status = 'active' then jsonb_build_object(
        'crm_code', requester_identity.crm_code, 'registration_date', requester_identity.registration_date,
        'signature_image_path', requester_identity.signature_image_path, 'rubric_image_path', requester_identity.rubric_image_path
      ) else null end
    ),
    'executed_by', jsonb_build_object(
      'id', responsible.user_id, 'name', responsible.display_name, 'position', responsible_position.name,
      'identity', case when responsible_identity.status = 'active' then jsonb_build_object(
        'crm_code', responsible_identity.crm_code, 'registration_date', responsible_identity.registration_date,
        'signature_image_path', responsible_identity.signature_image_path, 'rubric_image_path', responsible_identity.rubric_image_path
      ) else null end
    ),
    'reviewed_by', case when reviewer.user_id is null then null else jsonb_build_object(
      'id', reviewer.user_id, 'name', reviewer.display_name, 'position', reviewer_position.name,
      'identity', case when reviewer_identity.status = 'active' then jsonb_build_object(
        'crm_code', reviewer_identity.crm_code, 'registration_date', reviewer_identity.registration_date,
        'signature_image_path', reviewer_identity.signature_image_path, 'rubric_image_path', reviewer_identity.rubric_image_path
      ) else null end
    ) end,
    'dates', jsonb_build_object(
      'requested_at', exam.requested_at, 'started_at', exam.started_at,
      'submitted_for_review_at', exam.submitted_for_review_at, 'completed_at', exam.completed_at
    )
  ) into v_result
  from public.clinical_exams exam
  join public.patients patient on patient.id = exam.patient_id
  join public.exam_types exam_type on exam_type.id = exam.exam_type_id
  join public.exam_categories category on category.id = exam_type.category_id
  join public.profiles requester on requester.user_id = exam.requested_by
  left join public.staff_positions requester_position on requester_position.id = requester.position_id
  left join public.professional_identities requester_identity on requester_identity.user_id = requester.user_id
  join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
  left join public.staff_positions responsible_position on responsible_position.id = responsible.position_id
  left join public.professional_identities responsible_identity on responsible_identity.user_id = responsible.user_id
  left join public.profiles reviewer on reviewer.user_id = exam.reviewed_by
  left join public.staff_positions reviewer_position on reviewer_position.id = reviewer.position_id
  left join public.professional_identities reviewer_identity on reviewer_identity.user_id = reviewer.user_id
  where exam.id = p_exam_id;
  if v_result is null then raise exception 'Exame nao localizado.'; end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION private.build_clinical_exam_result(p_exam_type_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_result jsonb;
begin
  v_result := private.build_lab_result(p_exam_type_id);
  if v_result <> '{}'::jsonb then return v_result; end if;
  return private.build_image_result(p_exam_type_id);
end;
$function$;

CREATE OR REPLACE FUNCTION private.build_image_result(p_exam_type_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_code text;
  v_name text;
  v_config jsonb;
  v_snapshot jsonb;
begin
  select exam_type.code, exam_type.name, exam_type.result_config
  into v_code, v_name, v_config
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = p_exam_type_id
    and category.code = 'imagem'
    and exam_type.result_config->>'kind' = 'imaging';

  if v_config is null then return '{}'::jsonb; end if;
  perform private.assert_valid_image_template(v_config);
  v_snapshot := v_config || jsonb_build_object('exam_type_code', v_code, 'exam_type_name', v_name);

  return jsonb_build_object(
    'schema', 'hpsm.image_result.v1',
    'template_version', (v_config->>'version')::integer,
    'template_snapshot', v_snapshot,
    'region', '',
    'other_region', '',
    'laterality', case when (v_config->>'supports_laterality')::boolean then '' else 'not_applicable' end,
    'contrast', case when (v_config->>'supports_contrast')::boolean then '' else 'not_applicable' end,
    'notes', ''
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.build_lab_result(p_exam_type_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_code text;
  v_name text;
  v_config jsonb;
  v_snapshot jsonb;
  v_parameters jsonb;
begin
  select exam_type.code, exam_type.name, exam_type.result_config
  into v_code, v_name, v_config
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = p_exam_type_id
    and category.code = 'laboratorial'
    and exam_type.result_config->>'kind' = 'laboratory';

  if v_config is null then
    return '{}'::jsonb;
  end if;

  perform private.assert_valid_lab_template(v_config);
  v_snapshot := v_config || jsonb_build_object('exam_type_code', v_code, 'exam_type_name', v_name);

  select coalesce(jsonb_agg(
    parameter || jsonb_build_object('value', '', 'flag', null)
    order by (parameter->>'sort_order')::integer, parameter->>'label'
  ), '[]'::jsonb)
  into v_parameters
  from jsonb_array_elements(v_config->'parameters') parameter
  where (parameter->>'active')::boolean;

  return jsonb_build_object(
    'schema', 'hpsm.lab_result.v1',
    'template_version', (v_config->>'version')::integer,
    'template_snapshot', v_snapshot,
    'parameters', v_parameters,
    'notes', ''
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.can_access_clinical_exam_ai(p_actor uuid, p_exam_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p_actor is not null and exists (
    select 1
    from public.clinical_exams exam
    where exam.id = p_exam_id
      and (
        (exam.responsible_professional_id = p_actor and private.has_permission(p_actor, 'exams.perform'))
        or private.has_permission(p_actor, 'exams.review')
      )
  );
$function$;

CREATE OR REPLACE FUNCTION private.can_perform_clinical_exam(p_actor uuid, p_responsible uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p_actor is not null and (
    (p_actor = p_responsible and private.has_permission(p_actor, 'exams.perform'))
    or private.has_permission(p_actor, 'exams.review')
  );
$function$;

CREATE OR REPLACE FUNCTION private.can_view_notification(p_notification_id bigint, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.notifications notification
    join public.profiles profile on profile.user_id = p_user_id
    left join public.staff_positions position on position.id = profile.position_id
    where notification.id = p_notification_id
      and profile.status = 'active'
      and notification.archived_at is null
      and (notification.expires_at is null or notification.expires_at > now())
      and (
        notification.recipient_id = p_user_id
        or notification.audience = 'all'
        or (
          notification.audience = 'directors'
          and (
            (notification.required_permission is not null and private.has_permission(p_user_id, notification.required_permission))
            or (notification.required_permission is null and position.level >= 11)
          )
        )
        or (notification.audience = 'employees' and coalesce(position.level, 1) <= 10)
      )
  );
$function$;

CREATE OR REPLACE FUNCTION private.cancel_attendance(p_attendance_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.hpsm_current_actor();
  if not private.has_permission((select auth.uid()), 'attendances.manage') then
    raise exception 'Você não possui permissão para cancelar atendimentos.';
  end if;
  update public.attendances
  set status = 'cancelled', cancelled_by = (select auth.uid()), cancelled_at = now()
  where id = p_attendance_id and status = 'completed';
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION private.clinical_cast_location_label(p_body_region text, p_laterality text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select
    case p_body_region
      when 'hand' then 'Mão'
      when 'wrist' then 'Punho'
      when 'forearm' then 'Antebraço'
      when 'elbow' then 'Cotovelo'
      when 'arm' then 'Braço'
      when 'foot' then 'Pé'
      when 'ankle' then 'Tornozelo'
      when 'leg' then 'Perna'
      when 'knee' then 'Joelho'
      else 'Outro local'
    end
    || case p_laterality
      when 'right' then case when p_body_region in ('hand', 'leg') then ' direita' else ' direito' end
      when 'left' then case when p_body_region in ('hand', 'leg') then ' esquerda' else ' esquerdo' end
      when 'bilateral' then ' bilateral'
      else ''
    end;
$function$;

CREATE OR REPLACE FUNCTION private.clinical_exam_ai_report_values(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_findings text;
begin
  if p_payload->>'schema' = 'hpsm.ai.exam_bundle.v4' then
    p_payload := p_payload->'report' || jsonb_build_object('schema', 'hpsm.ai.clinical_report.v3');
  end if;
  if p_payload->>'schema' = 'hpsm.ai.clinical_report.v3' then
    select string_agg('- ' || btrim(item), E'\n') into v_findings from jsonb_array_elements_text(p_payload->'findings') item;
    return jsonb_build_object(
      'technique', nullif(btrim(p_payload->>'technique'), ''),
      'findings', nullif(v_findings, ''),
      'conclusion', nullif(btrim(p_payload->>'conclusion'), ''),
      'conduct', nullif(btrim(p_payload->>'conduct'), '')
    );
  elsif p_payload->>'schema' in ('hpsm.ai.simple_report.v1', 'hpsm.ai.simple_report.v2') then
    select string_agg('- ' || btrim(item), E'\n') into v_findings from jsonb_array_elements_text(p_payload->'findings') item;
    return jsonb_build_object(
      'technique', nullif(btrim(p_payload->>'summary'), ''),
      'findings', nullif(v_findings, ''),
      'conclusion', nullif(btrim(p_payload->>'conclusion'), ''),
      'conduct', case when p_payload->>'schema' = 'hpsm.ai.simple_report.v1' then nullif(btrim(p_payload->>'rp_note'), '') else null end
    );
  elsif p_payload->>'schema' = 'hpsm.ai.report_suggestion.v1' then
    return jsonb_build_object(
      'technique', nullif(btrim(p_payload#>>'{fields,technique}'), ''),
      'findings', nullif(btrim(p_payload#>>'{fields,findings}'), ''),
      'conclusion', nullif(btrim(p_payload#>>'{fields,conclusion}'), ''),
      'conduct', nullif(btrim(p_payload#>>'{fields,observations}'), '')
    );
  end if;
  raise exception 'Schema de laudo de IA incompatível.';
end;
$function$;

CREATE OR REPLACE FUNCTION private.clinical_exam_case_summary(p_indication text, p_context text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select left(
    case
      when nullif(btrim(coalesce(p_indication, '')), '') is null then btrim(coalesce(p_context, ''))
      when nullif(btrim(coalesce(p_context, '')), '') is null
        or btrim(p_context) = btrim(p_indication) then btrim(p_indication)
      else btrim(p_indication) || E'\n' || btrim(p_context)
    end,
    4000
  );
$function$;

CREATE OR REPLACE FUNCTION private.clinical_exam_document_state_json(p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_document public.clinical_exam_documents;
  v_share public.clinical_exam_document_shares;
begin
  select document.* into v_document
  from public.clinical_exam_documents document
  where document.exam_id = p_exam_id
    and document.render_version = 'exam-document-png-v4'
  order by document.created_at desc
  limit 1;

  if v_document.id is not null then
    select share.* into v_share
    from public.clinical_exam_document_shares share
    where share.exam_id = p_exam_id
      and share.document_id = v_document.id
      and share.revoked_at is null
    order by share.created_at desc
    limit 1;
  end if;

  return jsonb_build_object(
    'document', case when v_document.id is null then null else jsonb_build_object(
      'id', v_document.id,
      'created_at', v_document.created_at,
      'file_size', v_document.file_size,
      'pixel_width', v_document.pixel_width,
      'pixel_height', v_document.pixel_height,
      'render_version', v_document.render_version
    ) end,
    'share', case when v_share.id is null then null else jsonb_build_object(
      'id', v_share.id,
      'created_at', v_share.created_at
    ) end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.clinical_exam_report_config(p_exam_type_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_category_code text;
  v_type_code text;
  v_uses_technique boolean := true;
  v_requires_technique boolean := true;
  v_uses_findings boolean := true;
  v_requires_findings boolean := true;
  v_uses_conclusion boolean := true;
  v_requires_conclusion boolean := true;
  v_findings_label text := 'Achados';
begin
  select category.code, exam_type.code
  into v_category_code, v_type_code
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = p_exam_type_id;

  if v_category_code is null then
    raise exception 'Tipo de exame não localizado.';
  end if;

  if v_category_code = 'laboratorial' then
    v_uses_technique := false;
    v_requires_technique := false;
    v_findings_label := 'Interpretação';

    if v_type_code = 'tipagem_sanguinea' then
      v_uses_findings := false;
      v_requires_findings := false;
      v_uses_conclusion := false;
      v_requires_conclusion := false;
    end if;
  end if;

  return jsonb_build_object(
    'schema', 'hpsm.report_config.v1',
    'fields', jsonb_build_object(
      'technique', jsonb_build_object('visible', v_uses_technique, 'required', v_requires_technique, 'label', 'Técnica'),
      'findings', jsonb_build_object('visible', v_uses_findings, 'required', v_requires_findings, 'label', v_findings_label),
      'conclusion', jsonb_build_object('visible', v_uses_conclusion, 'required', v_requires_conclusion, 'label', 'Conclusão'),
      'observations', jsonb_build_object('visible', true, 'required', false, 'label', 'Observações')
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.clinical_text_contains_meta_language(p_value text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select lower(coalesce(p_value, '')) ~
    '(^|[^[:alnum:]_])(gta[[:space:]-]*rp|rp|role[[:space:]-]*play|fict(i|í)ci(o|a|os|as)|simula(ção|ções|cao|coes)|simulad(o|a|os|as)|personagem|personagens|video[[:space:]-]*game|videogame|game)([^[:alnum:]_]|$)';
$function$;

CREATE OR REPLACE FUNCTION private.close_health_plan_request_on_attendance_cancel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.status = 'completed' and new.status = 'cancelled' then
    update public.patient_health_plan_requests
    set status = 'rejected',
        reviewed_by = new.cancelled_by,
        reviewed_at = coalesce(new.cancelled_at, now()),
        rejection_reason = 'Atendimento de origem cancelado antes da confirmação do plano.'
    where attendance_id = new.id
      and status = 'pending';
  end if;
  return new;
end;
$function$;


CREATE OR REPLACE FUNCTION private.create_health_plan_request_from_sale()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_patient_id bigint;
  v_service_code text;
begin
  select catalog.code
  into v_service_code
  from public.service_catalog as catalog
  where catalog.id = new.service_id;

  if v_service_code is distinct from 'plano_saude_convenio' then
    return new;
  end if;

  if new.quantity <> 1 then
    raise exception 'O plano de saúde pode aparecer somente uma vez no atendimento.';
  end if;

  select attendance.patient_id
  into v_patient_id
  from public.attendances as attendance
  where attendance.id = new.attendance_id
    and attendance.status = 'completed';

  if not found then
    raise exception 'Atendimento do plano não localizado.';
  end if;

  insert into public.patient_health_plan_requests (patient_id, attendance_id)
  values (v_patient_id, new.attendance_id)
  on conflict (attendance_id) do nothing;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.current_position_level(p_user_id uuid)
 RETURNS smallint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select position.level
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  where profile.user_id = p_user_id and profile.status <> 'inactive' and position.active;
$function$;

CREATE OR REPLACE FUNCTION private.default_image_template(p_exam_type_code text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'schema', 'hpsm.image_template.v1',
    'kind', 'imaging',
    'version', 1,
    'region', jsonb_build_object(
      'required', true,
      'options', case p_exam_type_code
        when 'raio_x' then jsonb_build_array('Tórax','Abdome','Coluna cervical','Coluna torácica','Coluna lombar','Pelve','Ombro','Braço','Cotovelo','Antebraço','Punho','Mão','Quadril','Coxa','Joelho','Perna','Tornozelo','Pé','Crânio','Face','Outra região')
        when 'tomografia' then jsonb_build_array('Crânio','Seios da face','Pescoço','Tórax','Abdome','Pelve','Coluna','Membro superior','Membro inferior','Angiotomografia','Outra região')
        when 'ressonancia_magnetica' then jsonb_build_array('Crânio','Coluna cervical','Coluna torácica','Coluna lombar','Ombro','Cotovelo','Punho','Mão','Quadril','Joelho','Tornozelo','Pé','Abdome','Pelve','Outra região')
        when 'ultrassom' then jsonb_build_array('Abdome total','Abdome superior','Pelve','Obstétrico','Rins e vias urinárias','Tireoide','Mama','Partes moles','Musculoesquelético','Doppler vascular','Outra região')
        else jsonb_build_array('Outra região')
      end
    ),
    'supports_laterality', true,
    'supports_contrast', p_exam_type_code in ('tomografia', 'ressonancia_magnetica'),
    'requires_image', true,
    'allows_multiple_images', true
  );
$function$;

CREATE OR REPLACE FUNCTION private.discard_exam_ai_image_drafts_on_lock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.status = 'in_progress' and new.status in ('awaiting_review','completed') then
    update public.exam_ai_generations set status='discarded',discarded_at=now()
    where exam_id=new.id and generation_type='generate_image' and status='completed';
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION private.enforce_patient_birth_date()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.birth_date is not null and new.birth_date > current_date then
    raise exception 'A data de nascimento não pode estar no futuro.' using errcode = '23514';
  end if;

  if tg_op = 'INSERT' and new.birth_date is null then
    raise exception 'Informe a data de nascimento do paciente.' using errcode = '23514';
  end if;

  if tg_op = 'UPDATE'
     and new.birth_date is null
     and row(
       new.passport,
       new.name,
       new.phone,
       new.emergency_contact_name,
       new.emergency_contact_phone
     ) is distinct from row(
       old.passport,
       old.name,
       old.phone,
       old.emergency_contact_name,
       old.emergency_contact_phone
     ) then
    raise exception 'Informe a data de nascimento antes de alterar o cadastro.' using errcode = '23514';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.ensure_staff_promotion_review(p_employee_id uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_status jsonb;
  v_id bigint;
begin
  v_status := private.get_staff_progression_status(p_employee_id);
  if coalesce((v_status ->> 'eligible')::boolean, false) is not true then return null; end if;
  select id into v_id from public.staff_promotion_reviews
  where employee_id = p_employee_id and status in ('pending', 'deferred')
  order by created_at desc limit 1;
  if v_id is not null then return v_id; end if;
  insert into public.staff_promotion_reviews (
    employee_id, from_position_id, to_position_id, required_days,
    elapsed_days, worked_minutes, attendance_count, flagged_warning_count
  ) values (
    p_employee_id, (v_status ->> 'position_id')::bigint,
    (v_status ->> 'next_position_id')::bigint,
    (v_status ->> 'required_days')::smallint,
    (v_status ->> 'elapsed_days')::integer,
    (v_status ->> 'worked_minutes')::integer,
    (v_status ->> 'attendance_count')::integer,
    (v_status ->> 'flagged_warning_count')::integer
  ) returning id into v_id;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION private.exam_ai_payload_contains_meta_language(p_payload jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select private.clinical_text_contains_meta_language(coalesce(p_payload::text, ''));
$function$;

CREATE OR REPLACE FUNCTION private.get_staff_progression_status(p_employee_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles;
  v_position public.staff_positions;
  v_next public.staff_positions;
  v_rule public.staff_position_transition_rules;
  v_since timestamptz;
  v_elapsed integer := 0;
  v_worked integer := 0;
  v_attendances integer := 0;
  v_warnings integer := 0;
  v_required_days integer := 15;
  v_eligible boolean := false;
begin
  select * into v_profile from public.profiles where user_id = p_employee_id;
  if not found or v_profile.position_id is null then
    return jsonb_build_object('employee_id', p_employee_id, 'eligible', false, 'reason', 'Cargo não definido');
  end if;
  select * into v_position from public.staff_positions where id = v_profile.position_id;
  if v_position.level >= 10 then
    return jsonb_build_object(
      'employee_id', p_employee_id, 'position_id', v_position.id,
      'level', v_position.level, 'eligible', false,
      'reason', case when v_position.level = 10 then 'Próximo cargo depende de nomeação' else 'Cargo de gestão' end
    );
  end if;
  select * into v_next from public.staff_positions where level = v_position.level + 1 and active;
  select * into v_rule from public.staff_position_transition_rules
  where from_position_id = v_position.id and to_position_id = v_next.id and active;
  select coalesce(max(history.effective_at), v_profile.created_at) into v_since
  from public.staff_position_history history
  where history.employee_id = p_employee_id and history.to_position_id = v_position.id;
  v_elapsed := greatest(0, floor(extract(epoch from (now() - v_since)) / 86400)::integer);
  v_worked := private.staff_worked_minutes_since(p_employee_id, v_since);
  select count(*)::integer into v_attendances
  from public.attendances attendance
  where attendance.performed_by = p_employee_id
    and attendance.status = 'completed'
    and attendance.created_at >= v_since;
  select count(*)::integer into v_warnings
  from public.rh_warnings warning
  where warning.employee_id = p_employee_id
    and warning.status = 'active'
    and warning.impacts_progression
    and warning.issued_at >= v_since;
  v_required_days := case when v_warnings = 0 then v_rule.min_days when v_warnings = 1 then 30 else 60 end;
  v_eligible := v_profile.status = 'active'
    and v_warnings < 3
    and v_elapsed >= v_required_days
    and v_worked >= v_rule.min_worked_minutes
    and v_attendances >= v_rule.min_attendances;
  return jsonb_build_object(
    'employee_id', p_employee_id,
    'position_id', v_position.id,
    'position_name', v_position.name,
    'level', v_position.level,
    'next_position_id', v_next.id,
    'next_position_name', v_next.name,
    'since', v_since,
    'elapsed_days', v_elapsed,
    'required_days', v_required_days,
    'worked_minutes', v_worked,
    'required_worked_minutes', v_rule.min_worked_minutes,
    'attendance_count', v_attendances,
    'required_attendances', v_rule.min_attendances,
    'flagged_warning_count', v_warnings,
    'eligible', v_eligible,
    'blocked', v_warnings >= 3 or v_profile.status <> 'active'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_attendance_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if old.status <> 'completed' then
    raise exception 'Um atendimento cancelado não pode ser alterado.';
  end if;

  if new.patient_id is distinct from old.patient_id
     or new.patient_name is distinct from old.patient_name
     or new.patient_passport is distinct from old.patient_passport
     or new.plan_code is distinct from old.plan_code
     or new.plan_name is distinct from old.plan_name
     or new.subtotal is distinct from old.subtotal
     or new.discount is distinct from old.discount
     or new.notes is distinct from old.notes
     or new.performed_by is distinct from old.performed_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Os dados financeiros do atendimento são imutáveis.';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_clinical_cast_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if old.status in ('removed', 'cancelled') then
    raise exception 'Este registro clínico já foi encerrado e não pode ser alterado.';
  end if;
  if new.patient_id is distinct from old.patient_id
     or new.attendance_id is distinct from old.attendance_id
     or new.body_region is distinct from old.body_region
     or new.laterality is distinct from old.laterality
     or new.applied_at is distinct from old.applied_at
     or new.applied_by is distinct from old.applied_by
     or new.application_notes is distinct from old.application_notes
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Os dados da aplicação de gesso são históricos e não podem ser substituídos.';
  end if;
  if new.status not in ('in_use', 'removed', 'cancelled') then
    raise exception 'Transição de status inválida.';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_director_general()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if old.role_code = 'diretor_geral'
     and (new.role_code <> 'diretor_geral' or new.status <> 'active')
     and current_setting('hpsm.position_change_authorized', true) <> 'true' then
    raise exception 'A conta do Diretor Geral só pode ser alterada pelo fluxo de sucessão.';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_patient_plan_changes()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if (tg_op = 'INSERT' and new.plan_code is not null)
     or (tg_op = 'UPDATE' and new.plan_code is distinct from old.plan_code) then
    raise exception 'O benefício deve ser escolhido no atendimento; o Plano HPSM é ativado pela conferência de pagamento.';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_profile_position_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.position_id is distinct from old.position_id
     and current_setting('hpsm.position_change_authorized', true) <> 'true' then
    raise exception 'Altere o cargo somente pelos fluxos de promoção ou nomeação.';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.has_any_management_permission(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.system_permissions permission
    where private.has_permission(p_user_id, permission.code)
  );
$function$;

CREATE OR REPLACE FUNCTION private.has_permission(p_user_id uuid, p_permission_code text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.profiles profile
    join public.staff_positions current_position
      on current_position.id = profile.position_id
     and current_position.active
    where profile.user_id = p_user_id
      and profile.status = 'active'
      and not profile.must_change_password
      and ((select auth.uid()) is null or private.hpsm_session_valid())
      and (
        p_permission_code <> 'recruitment.manage'
        or current_position.level between 11 and 14
      )
      and (
        exists (
          select 1
          from public.staff_position_permissions position_permission
          join public.staff_positions position on position.id = position_permission.position_id
          where position_permission.position_id = profile.position_id
            and position_permission.permission_code = p_permission_code
            and position.active
        )
        or exists (
          select 1
          from public.user_permission_grants permission_grant
          where permission_grant.user_id = profile.user_id
            and permission_grant.permission_code = p_permission_code
            and permission_grant.revoked_at is null
            and permission_grant.valid_from <= now()
            and (permission_grant.expires_at is null or permission_grant.expires_at > now())
        )
      )
  );
$function$;

CREATE OR REPLACE FUNCTION private.hpsm_auth_actor()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_session_id uuid;
begin
  begin
    v_session_id := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  exception when invalid_text_representation then
    v_session_id := null;
  end;

  if v_actor is null
     or v_session_id is null
     or not exists (
       select 1
       from auth.sessions session
       join auth.users auth_user on auth_user.id = session.user_id
       join public.profiles profile on profile.user_id = session.user_id
       where session.id = v_session_id
         and session.user_id = v_actor
         and (session.not_after is null or session.not_after > now())
         and auth_user.deleted_at is null
         and (auth_user.banned_until is null or auth_user.banned_until <= now())
         and profile.status = 'active'
     ) then
    raise exception 'Sessão inválida ou expirada.' using errcode = '42501';
  end if;

  return v_actor;
end;
$function$;

CREATE OR REPLACE FUNCTION private.hpsm_build_internal_crm(p_passport text, p_registration_date date)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
begin
  if p_passport is null or p_passport !~ '^[0-9]{1,4}$' or p_registration_date is null then
    raise exception 'Dados insuficientes para gerar o CRM interno.' using errcode = '22023';
  end if;
  return lpad(p_passport, 4, '0') || to_char(p_registration_date, 'DDMM');
end;
$function$;

CREATE OR REPLACE FUNCTION private.hpsm_current_actor()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid := private.hpsm_auth_actor();
begin
  if exists (select 1 from public.profiles where user_id = v_actor and must_change_password) then
    raise exception 'Altere sua senha antes de acessar o sistema.' using errcode = '42501';
  end if;
  return v_actor;
end; $function$;

CREATE OR REPLACE FUNCTION private.hpsm_dashboard_config_valid(p_config jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_allowed_widgets constant text[] := array[
    'my_week', 'my_production', 'career', 'attention',
    'communications', 'shortcuts', 'hospital_overview'
  ];
  v_allowed_shortcuts constant text[] := array[
    'overview', 'new_attendance', 'attendances', 'patients', 'catalog',
    'exams', 'casts', 'my_hr', 'administrative', 'pending', 'rh',
    'career', 'recruitment', 'partnerships', 'team', 'profiles', 'reports',
    'audit', 'communications'
  ];
  v_breakpoint text;
  v_cols integer;
  v_layout jsonb;
  v_count integer;
  v_unique_count integer;
  v_valid boolean;
begin
  if p_config is null
     or jsonb_typeof(p_config) <> 'object'
     or pg_column_size(p_config) > 32768
     or p_config - array['configVersion', 'layouts', 'hiddenWidgets', 'shortcuts'] <> '{}'::jsonb
     or not (p_config ?& array['configVersion', 'layouts', 'hiddenWidgets', 'shortcuts'])
     or p_config ->> 'configVersion' <> '1'
     or jsonb_typeof(p_config -> 'layouts') <> 'object'
     or jsonb_typeof(p_config -> 'hiddenWidgets') <> 'array'
     or jsonb_typeof(p_config -> 'shortcuts') <> 'array'
  then
    return false;
  end if;

  select count(*) into v_count from jsonb_object_keys(p_config -> 'layouts');
  if v_count <> 3 or not (p_config -> 'layouts' ?& array['lg', 'md', 'sm']) then return false; end if;

  foreach v_breakpoint in array array['lg', 'md', 'sm'] loop
    v_cols := case v_breakpoint when 'lg' then 12 when 'md' then 8 else 1 end;
    v_layout := p_config -> 'layouts' -> v_breakpoint;
    if jsonb_typeof(v_layout) <> 'array' or jsonb_array_length(v_layout) <> 7 then return false; end if;

    select count(*), count(distinct item ->> 'i'), coalesce(bool_and(
      jsonb_typeof(item) = 'object'
      and item - array['i', 'x', 'y', 'w', 'h'] = '{}'::jsonb
      and item ?& array['i', 'x', 'y', 'w', 'h']
      and item ->> 'i' = any(v_allowed_widgets)
      and (item ->> 'x') ~ '^[0-9]+$'
      and (item ->> 'y') ~ '^[0-9]+$'
      and (item ->> 'w') ~ '^[0-9]+$'
      and (item ->> 'h') ~ '^[0-9]+$'
      and (item ->> 'x')::integer between 0 and v_cols - 1
      and (item ->> 'y')::integer between 0 and 240
      and (item ->> 'w')::integer between 1 and v_cols
      and (item ->> 'h')::integer between 4 and 40
      and (item ->> 'x')::integer + (item ->> 'w')::integer <= v_cols
    ), false)
    into v_count, v_unique_count, v_valid
    from jsonb_array_elements(v_layout) item;

    if v_count <> 7 or v_unique_count <> 7 or not v_valid then return false; end if;

    if exists (
      select 1
      from jsonb_array_elements(v_layout) with ordinality left_item(item, position)
      join jsonb_array_elements(v_layout) with ordinality right_item(item, position)
        on left_item.position < right_item.position
      where left_item.item ->> 'i' not in ('shortcuts', 'hospital_overview')
        and right_item.item ->> 'i' not in ('shortcuts', 'hospital_overview')
        and not (p_config -> 'hiddenWidgets' ? (left_item.item ->> 'i'))
        and not (p_config -> 'hiddenWidgets' ? (right_item.item ->> 'i'))
        and (left_item.item ->> 'x')::integer < (right_item.item ->> 'x')::integer + (right_item.item ->> 'w')::integer
        and (left_item.item ->> 'x')::integer + (left_item.item ->> 'w')::integer > (right_item.item ->> 'x')::integer
        and (left_item.item ->> 'y')::integer < (right_item.item ->> 'y')::integer + (right_item.item ->> 'h')::integer
        and (left_item.item ->> 'y')::integer + (left_item.item ->> 'h')::integer > (right_item.item ->> 'y')::integer
    ) then return false; end if;
  end loop;

  select count(*), count(distinct value), coalesce(bool_and(value = any(v_allowed_widgets)), false)
  into v_count, v_unique_count, v_valid
  from jsonb_array_elements_text(p_config -> 'hiddenWidgets') value;
  if v_count > 7 or v_count <> v_unique_count or (v_count > 0 and not v_valid) then return false; end if;

  select count(*), count(distinct value), coalesce(bool_and(value = any(v_allowed_shortcuts)), false)
  into v_count, v_unique_count, v_valid
  from jsonb_array_elements_text(p_config -> 'shortcuts') value;
  if v_count > 19 or v_count <> v_unique_count or (v_count > 0 and not v_valid) then return false; end if;

  return true;
exception when others then return false;
end;
$function$;

CREATE OR REPLACE FUNCTION private.hpsm_identity_is_director_general(p_actor uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id
    where profile.user_id = p_actor
      and profile.status = 'active'
      and profile.must_change_password = false
      and position.active
      and position.official
      and position.level = 14
  );
$function$;

CREATE OR REPLACE FUNCTION private.hpsm_professional_registration_date(p_user_id uuid)
 RETURNS date
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    (select (min(history.effective_at) at time zone 'America/Sao_Paulo')::date
       from public.staff_position_history history
      where history.employee_id = profile.user_id
        and history.event_type = 'initial_assignment'),
    (profile.created_at at time zone 'America/Sao_Paulo')::date
  )
  from public.profiles profile
  where profile.user_id = p_user_id;
$function$;

CREATE OR REPLACE FUNCTION private.hpsm_report_hours(p_start_date date, p_end_date date)
 RETURNS TABLE(employee_id uuid, worked_minutes bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with months as (
    select month_value::date as month_start
    from pg_catalog.generate_series(
      pg_catalog.date_trunc('month', p_start_date::timestamp)::date,
      pg_catalog.date_trunc('month', p_end_date::timestamp)::date,
      interval '1 month'
    ) month_value
  ), eligible as (
    select profile.user_id
    from public.profiles profile
    where profile.role_code <> 'diretor_geral'
      and profile.status in ('active', 'suspended')
  ), boundaries as (
    select
      eligible.user_id as employee_id,
      months.month_start,
      greatest(p_start_date, months.month_start) as range_start,
      least(p_end_date, (months.month_start + interval '1 month - 1 day')::date) as range_end
    from eligible cross join months
  ), measured as (
    select
      boundary.employee_id,
      boundary.month_start,
      boundary.range_start,
      ending.total_minutes as ending_minutes,
      baseline.total_minutes as baseline_minutes
    from boundaries boundary
    left join lateral (
      select snapshot.total_minutes
      from public.rh_hour_snapshots snapshot
      where snapshot.employee_id = boundary.employee_id
        and snapshot.reference_month = boundary.month_start
        and snapshot.reading_date <= boundary.range_end
      order by snapshot.reading_date desc, snapshot.updated_at desc, snapshot.id desc
      limit 1
    ) ending on true
    left join lateral (
      select snapshot.total_minutes
      from public.rh_hour_snapshots snapshot
      where snapshot.employee_id = boundary.employee_id
        and snapshot.reference_month = boundary.month_start
        and snapshot.reading_date < boundary.range_start
      order by snapshot.reading_date desc, snapshot.updated_at desc, snapshot.id desc
      limit 1
    ) baseline on true
  )
  select
    measured.employee_id,
    coalesce(sum(greatest(
      measured.ending_minutes - case when measured.range_start = measured.month_start then 0 else measured.baseline_minutes end,
      0
    )), 0)::bigint as worked_minutes
  from measured
  where measured.ending_minutes is not null
    and (measured.range_start = measured.month_start or measured.baseline_minutes is not null)
  group by measured.employee_id;
$function$;

CREATE OR REPLACE FUNCTION private.hpsm_report_validate_period(p_start_date date, p_end_date date)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
begin
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Período inválido.' using errcode = '22023';
  end if;
  if (p_end_date - p_start_date) > 366 then
    raise exception 'O período detalhado deve ter no máximo 12 meses.' using errcode = '22023';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION private.hpsm_session_valid(p_require_ready boolean DEFAULT true)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_require_ready then perform private.hpsm_current_actor(); else perform private.hpsm_auth_actor(); end if;
  return true;
exception when insufficient_privilege then return false;
end; $function$;

CREATE OR REPLACE FUNCTION private.is_active_user()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.hpsm_session_valid();
$function$;

CREATE OR REPLACE FUNCTION private.is_director()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.profiles
    where user_id = (select auth.uid())
      and status = 'active'
      and role_code in ('diretor_geral', 'diretoria')
  );
$function$;

CREATE OR REPLACE FUNCTION private.is_director_user(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p_user_id is not null and exists (
    select 1
    from public.profiles
    where user_id = p_user_id
      and status = 'active'
      and role_code in ('diretor_geral', 'diretoria')
  );
$function$;

CREATE OR REPLACE FUNCTION private.normalize_ai_clinical_exam_image_metadata()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.source = 'ai_generated' then
    new.original_filename := 'imagem-gerada-ia.png';
    new.caption := 'Imagem gerada por IA.';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.normalize_image_result(p_existing jsonb, p_candidate jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_snapshot jsonb;
  v_region text;
  v_other_region text;
  v_laterality text;
  v_contrast text;
  v_notes text;
begin
  if p_existing->>'schema' <> 'hpsm.image_result.v1'
     or jsonb_typeof(p_existing->'template_snapshot') <> 'object' then
    raise exception 'O resultado de imagem não possui um snapshot válido.';
  end if;
  if p_candidate is null
     or jsonb_typeof(p_candidate) <> 'object'
     or p_candidate->>'schema' <> 'hpsm.image_result.v1'
     or p_candidate->'template_snapshot' is distinct from p_existing->'template_snapshot'
     or p_candidate->'template_version' is distinct from p_existing->'template_version' then
    raise exception 'O snapshot do template não pode ser alterado.';
  end if;

  v_snapshot := p_existing->'template_snapshot';
  v_region := left(btrim(coalesce(p_candidate->>'region', '')), 120);
  v_other_region := left(btrim(coalesce(p_candidate->>'other_region', '')), 160);
  v_laterality := coalesce(p_candidate->>'laterality', '');
  v_contrast := coalesce(p_candidate->>'contrast', '');
  v_notes := left(coalesce(p_candidate->>'notes', ''), 4000);

  if v_region <> '' and not exists (
    select 1 from jsonb_array_elements_text(v_snapshot#>'{region,options}') option_value
    where option_value = v_region
  ) then raise exception 'Região inválida para este exame.'; end if;
  if v_region = 'Outra região' and v_other_region = '' then
    raise exception 'Informe a outra região examinada.';
  end if;
  if v_region <> 'Outra região' then v_other_region := ''; end if;

  if (v_snapshot->>'supports_laterality')::boolean then
    if v_laterality not in ('', 'left', 'right', 'bilateral', 'not_applicable') then
      raise exception 'Lateralidade inválida.';
    end if;
  else
    v_laterality := 'not_applicable';
  end if;

  if (v_snapshot->>'supports_contrast')::boolean then
    if v_contrast not in ('', 'with', 'without', 'not_applicable') then
      raise exception 'Uso de contraste inválido.';
    end if;
  else
    v_contrast := 'not_applicable';
  end if;

  return jsonb_build_object(
    'schema', 'hpsm.image_result.v1',
    'template_version', p_existing->'template_version',
    'template_snapshot', v_snapshot,
    'region', v_region,
    'other_region', v_other_region,
    'laterality', v_laterality,
    'contrast', v_contrast,
    'notes', v_notes
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.normalize_lab_result(p_existing jsonb, p_candidate jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_snapshot jsonb;
  v_parameters jsonb;
  v_notes text;
begin
  if p_existing->>'schema' <> 'hpsm.lab_result.v1'
     or jsonb_typeof(p_existing->'template_snapshot') <> 'object'
     or jsonb_typeof(p_existing->'parameters') <> 'array' then
    raise exception 'O resultado laboratorial não possui um snapshot válido.';
  end if;
  if p_candidate is null
     or jsonb_typeof(p_candidate) <> 'object'
     or p_candidate->>'schema' <> 'hpsm.lab_result.v1'
     or jsonb_typeof(p_candidate->'parameters') <> 'array'
     or p_candidate->'template_snapshot' is distinct from p_existing->'template_snapshot'
     or p_candidate->'template_version' is distinct from p_existing->'template_version' then
    raise exception 'O snapshot do template não pode ser alterado.';
  end if;

  if jsonb_array_length(p_candidate->'parameters') > 100
     or (select count(*) <> count(distinct parameter->>'key') from jsonb_array_elements(p_candidate->'parameters') parameter)
     or exists (
       select 1
       from jsonb_array_elements(p_candidate->'parameters') parameter
       where coalesce(parameter->>'key', '') = ''
          or char_length(coalesce(parameter->>'value', '')) > 2000
          or (parameter->'flag' is not null and jsonb_typeof(parameter->'flag') <> 'null'
              and coalesce(parameter->>'flag', '') not in ('normal', 'low', 'high', 'positive', 'negative', 'inconclusive'))
          or not exists (
            select 1
            from jsonb_array_elements(p_existing#>'{template_snapshot,parameters}') snapshot_parameter
            where snapshot_parameter->>'key' = parameter->>'key'
          )
     ) then
    raise exception 'Os parâmetros do resultado são inválidos.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_candidate->'parameters') candidate
    join jsonb_array_elements(p_existing#>'{template_snapshot,parameters}') snapshot
      on snapshot->>'key' = candidate->>'key'
    where nullif(btrim(candidate->>'value'), '') is not null
      and (
        (snapshot->>'field_type' in ('number', 'percent') and candidate->>'value' !~ '^-?[0-9]+([.,][0-9]+)?$')
        or (snapshot->>'field_type' = 'select' and not exists (
          select 1 from jsonb_array_elements_text(snapshot->'options') option_value
          where option_value = candidate->>'value'
        ))
      )
  ) then
    raise exception 'Há valores incompatíveis com o tipo configurado.';
  end if;

  v_snapshot := p_existing->'template_snapshot';
  v_notes := left(coalesce(p_candidate->>'notes', ''), 12000);

  select coalesce(jsonb_agg(
    snapshot_parameter || jsonb_build_object(
      'value', coalesce(candidate_parameter.candidate->>'value', ''),
      'flag', case
        when candidate_parameter.candidate->'flag' is null or jsonb_typeof(candidate_parameter.candidate->'flag') = 'null' then null
        else to_jsonb(candidate_parameter.candidate->>'flag')
      end
    ) order by (snapshot_parameter->>'sort_order')::integer, snapshot_parameter->>'label'
  ), '[]'::jsonb)
  into v_parameters
  from jsonb_array_elements(v_snapshot->'parameters') snapshot_parameter
  left join lateral (
    select candidate
    from jsonb_array_elements(p_candidate->'parameters') candidate
    where candidate->>'key' = snapshot_parameter->>'key'
    limit 1
  ) candidate_parameter on true
  where (snapshot_parameter->>'active')::boolean;

  return jsonb_build_object(
    'schema', 'hpsm.lab_result.v1',
    'template_version', p_existing->'template_version',
    'template_snapshot', v_snapshot,
    'parameters', v_parameters,
    'notes', v_notes
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.notify_absence_workflow()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notifications (
      kind, audience, priority, title, body, action_url, created_by,
      source_type, source_id, required_permission
    ) values (
      'system', 'directors', 'important', 'Novo afastamento solicitado',
      'Um afastamento preventivo aguarda análise e definição das horas abatidas.',
      '/rh?aba=absences', new.employee_id,
      'rh_leave', new.id::text, 'hr.absences.review'
    );
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status in ('approved', 'rejected', 'cancelled') then
    perform private.resolve_flow_notifications('rh_leave', new.id::text, coalesce(new.reviewed_by, new.cancelled_by, new.employee_id));
    if new.status in ('approved', 'rejected') then
      insert into public.notifications (
        kind, recipient_id, priority, title, body, action_url, created_by
      ) values (
        'personal', new.employee_id,
        case when new.status = 'approved' then 'normal' else 'important' end,
        case when new.status = 'approved' then 'Afastamento aprovado' else 'Afastamento recusado' end,
        case when new.status = 'approved'
          then 'Seu afastamento foi aprovado e as horas autorizadas já foram abatidas das metas atingidas.'
          else 'Seu afastamento foi recusado. Consulte o Meu RH para ver a decisão registrada.' end,
        '/meu-rh', new.reviewed_by
      );
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.notify_disciplinary_workflow()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notifications (
      kind, audience, priority, title, body, action_url, created_by,
      source_type, source_id, required_permission
    ) values (
      'system', 'directors', 'urgent', 'Análise disciplinar urgente',
      'Um colaborador atingiu três advertências no ciclo e foi suspenso para análise.',
      '/rh?aba=discipline', new.triggered_by,
      'rh_disciplinary_review', new.id::text, 'hr.discipline.manage'
    );
  elsif tg_op = 'UPDATE' and old.status in ('pending', 'suspension_maintained') and new.status <> old.status then
    perform private.resolve_flow_notifications('rh_disciplinary_review', new.id::text, new.decided_by);
    if new.status <> 'pending' then
      insert into public.notifications (
        kind, recipient_id, priority, title, body, action_url, created_by
      ) values (
        'personal', new.employee_id,
        case when new.status = 'reactivated' then 'normal' else 'important' end,
        case
          when new.status = 'reactivated' then 'Acesso reativado'
          when new.status = 'dismissed' then 'Desligamento registrado'
          else 'Suspensão mantida'
        end,
        case
          when new.status = 'reactivated' then 'A análise disciplinar foi concluída e seu acesso foi reativado.'
          when new.status = 'dismissed' then 'A análise disciplinar foi concluída com o desligamento do hospital.'
          else 'A análise disciplinar foi concluída e a suspensão foi mantida.'
        end,
        '/meu-rh', new.decided_by
      );
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.notify_health_plan_workflow()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_seller_id uuid;
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    select attendance.performed_by
    into v_seller_id
    from public.attendances as attendance
    where attendance.id = new.attendance_id;

    insert into public.notifications (
      kind, audience, priority, title, body, action_url, created_by,
      source_type, source_id, required_permission
    ) values (
      'system', 'directors', 'important', 'Plano de saúde aguardando confirmação',
      'Uma venda do Plano de Saúde HPSM aguarda conferência do pagamento e decisão de ativação.',
      '/rh?aba=pendencias#planos-saude', v_seller_id,
      'health_plan_request', new.id::text, 'healthplans.review'
    );
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status in ('approved', 'rejected') then
    perform private.resolve_flow_notifications('health_plan_request', new.id::text, new.reviewed_by);
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.notify_hr_hour_justification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notifications (
      kind, audience, priority, title, body, action_url, created_by,
      source_type, source_id, required_permission
    ) values (
      'system', 'directors', 'important', 'Justificativa de horas recebida',
      'Um colaborador respondeu a uma pendência semanal e aguarda análise.',
      '/rh?aba=absences', new.employee_id,
      'rh_hour_justification', new.id::text, 'hr.justifications.review'
    );
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status in ('approved', 'rejected') then
    perform private.resolve_flow_notifications('rh_hour_justification', new.id::text, new.reviewed_by);
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by
    ) values (
      'personal', new.employee_id,
      case when new.status = 'approved' then 'normal' else 'important' end,
      case when new.status = 'approved' then 'Justificativa de horas analisada' else 'Justificativa de horas recusada' end,
      case when new.status = 'approved'
        then format('Foram abonadas %sh%s do déficit informado. O resultado da semana foi recalculado.',
          new.credited_minutes / 60, lpad((new.credited_minutes % 60)::text, 2, '0'))
        else 'A justificativa foi recusada e o déficit da semana foi mantido.' end,
      '/meu-rh', new.reviewed_by
    );
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.notify_hr_week_deficit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.closure_status = 'awaiting_justification'
     and (tg_op = 'INSERT' or old.closure_status is distinct from new.closure_status) then
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by,
      source_type, source_id
    ) values (
      'personal', new.employee_id, 'important', 'Justifique as horas da semana',
      format('A apuração de %s a %s identificou déficit de %sh%s. Envie sua justificativa pelo Meu RH.',
        to_char(new.week_start, 'DD/MM'), to_char(new.week_end, 'DD/MM'),
        new.remaining_deficit_minutes / 60, lpad((new.remaining_deficit_minutes % 60)::text, 2, '0')),
      '/meu-rh', new.closed_by,
      'rh_weekly_deficit', new.id::text
    );
  elsif tg_op = 'UPDATE' and old.closure_status = 'awaiting_justification'
        and new.closure_status <> 'awaiting_justification' then
    perform private.resolve_flow_notifications('rh_weekly_deficit', new.id::text, new.employee_id);
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.notify_recruitment_submission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' and new.status in ('submitted', 'under_review', 'interview') then
    insert into public.notifications (
      kind, audience, priority, title, body, action_url,
      source_type, source_id, required_permission
    ) values (
      'system', 'directors', 'normal', 'Nova candidatura recebida',
      'Uma nova candidatura aguarda avaliação na fila de recrutamento.',
      '/rh?aba=candidaturas&selecionar=' || new.id::text,
      'recruitment_application', new.id::text, 'recruitment.manage'
    );
  elsif tg_op = 'UPDATE' and old.status in ('submitted', 'under_review', 'interview')
        and new.status in ('approved', 'rejected') then
    perform private.resolve_flow_notifications('recruitment_application', new.id::text, new.reviewed_by);
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.notify_staff_promotion_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notifications (
      kind, audience, priority, title, body, action_url, created_by,
      source_type, source_id, required_permission
    ) values (
      'system', 'directors', 'important', 'Promoção elegível para análise',
      'Um colaborador atingiu os requisitos mínimos. A promoção continua dependendo de decisão humana.',
      '/rh?aba=career', new.employee_id,
      'staff_promotion_review', new.id::text, 'progression.review'
    );
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.notify_warning_workflow()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' then
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by
    ) values (
      'personal', new.employee_id,
      case when new.sequence_in_cycle = 3 then 'urgent' else 'important' end,
      format('%sª advertência do ciclo', new.sequence_in_cycle),
      case
        when new.sequence_in_cycle = 3
          then 'A terceira advertência do ciclo foi registrada e seu acesso foi suspenso para análise da Diretoria.'
        else format('Uma advertência foi registrada. Contagem atual: %s/3 neste ciclo mensal.', new.sequence_in_cycle)
      end,
      '/meu-rh', new.issued_by
    );
  elsif tg_op = 'UPDATE' and old.status = 'active' and new.status = 'annulled' then
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by
    ) values (
      'personal', new.employee_id, 'normal', 'Advertência anulada',
      'Uma advertência deste ciclo foi anulada pela Diretoria e deixou de contar no limite mensal.',
      '/meu-rh', new.annulled_by
    );
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.partnership_apply_people(p_partnership_id bigint, p_people jsonb, p_origin text, p_actor_user_id uuid, p_actor_patient_id bigint, p_source text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_partnership public.partnerships%rowtype;
  v_entry jsonb;
  v_patient public.patients%rowtype;
  v_membership_id bigint;
  v_pending_id bigint;
  v_passport text;
  v_name text;
  v_line integer := 0;
  v_result text;
  v_items jsonb := '[]'::jsonb;
  v_linked integer := 0;
  v_existing integer := 0;
  v_pending integer := 0;
  v_review integer := 0;
  v_invalid integer := 0;
begin
  select * into v_partnership
  from public.partnerships partnership
  where partnership.id = p_partnership_id
  for update;

  if not found then raise exception 'Parceria não localizada.' using errcode = '22023'; end if;
  if v_partnership.status <> 'active' then
    raise exception 'Esta parceria está inativa e não permite novas inclusões.' using errcode = '22023';
  end if;
  if p_origin not in ('professional', 'partnership_responsible') then
    raise exception 'Origem inválida.' using errcode = '22023';
  end if;
  if p_source not in ('individual', 'batch') then
    raise exception 'Origem da inclusão inválida.' using errcode = '22023';
  end if;
  if p_people is null or jsonb_typeof(p_people) <> 'array' or jsonb_array_length(p_people) < 1 or jsonb_array_length(p_people) > 500 then
    raise exception 'Informe entre 1 e 500 pessoas por operação.' using errcode = '22023';
  end if;

  for v_entry in select value from jsonb_array_elements(p_people)
  loop
    v_line := v_line + 1;
    v_passport := btrim(coalesce(v_entry ->> 'passport', ''));
    v_name := btrim(coalesce(v_entry ->> 'name', ''));
    v_membership_id := null;
    v_pending_id := null;

    if jsonb_typeof(v_entry) <> 'object'
       or v_passport !~ '^[0-9]{1,4}$'
       or char_length(v_name) not between 2 and 120 then
      v_result := 'invalid';
      v_invalid := v_invalid + 1;
    else
      select * into v_patient
      from public.patients patient
      where patient.passport = v_passport;

      if found and private.partnership_name_key(v_patient.name) = private.partnership_name_key(v_name) then
        insert into public.patient_partnerships (
          patient_id, partnership_id, linked_by_type, linked_by_user_id, linked_by_patient_id
        ) values (
          v_patient.id, p_partnership_id, p_origin, p_actor_user_id, p_actor_patient_id
        )
        on conflict (partnership_id, patient_id) where status = 'active' do nothing
        returning id into v_membership_id;

        update public.partnership_pending_beneficiaries pending_beneficiary
        set status = 'resolved', resolved_at = now(), resolved_patient_id = v_patient.id
        where pending_beneficiary.partnership_id = p_partnership_id
          and pending_beneficiary.passport = v_passport
          and pending_beneficiary.status in ('pending_registration', 'name_review');

        if v_membership_id is null then
          v_result := 'already_linked';
          v_existing := v_existing + 1;
        else
          v_result := 'linked';
          v_linked := v_linked + 1;
        end if;
      elsif found then
        insert into public.partnership_pending_beneficiaries (
          partnership_id, passport, informed_name, status, source,
          created_by_type, created_by_user_id, created_by_patient_id
        ) values (
          p_partnership_id, v_passport, v_name, 'name_review', p_source,
          p_origin, p_actor_user_id, p_actor_patient_id
        )
        on conflict (partnership_id, passport) where status in ('pending_registration', 'name_review')
        do update set informed_name = excluded.informed_name, status = 'name_review'
        returning id into v_pending_id;
        v_result := 'name_review';
        v_review := v_review + 1;
      else
        insert into public.partnership_pending_beneficiaries (
          partnership_id, passport, informed_name, status, source,
          created_by_type, created_by_user_id, created_by_patient_id
        ) values (
          p_partnership_id, v_passport, v_name, 'pending_registration', p_source,
          p_origin, p_actor_user_id, p_actor_patient_id
        )
        on conflict (partnership_id, passport) where status in ('pending_registration', 'name_review')
        do update set informed_name = excluded.informed_name
        returning id into v_pending_id;
        v_result := 'pending_registration';
        v_pending := v_pending + 1;
      end if;
    end if;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'line', v_line,
      'passport', v_passport,
      'name', v_name,
      'result', v_result
    ));
  end loop;

  perform private.partnership_audit(
    case when jsonb_array_length(p_people) = 1 then 'PARTNERSHIP_PERSON_ADDED' else 'PARTNERSHIP_BATCH_IMPORTED' end,
    'partnerships', p_partnership_id::text, p_origin, p_actor_user_id, p_actor_patient_id,
    null,
    jsonb_build_object(
      'partnership_name', v_partnership.name,
      'source', p_source,
      'total', jsonb_array_length(p_people),
      'linked', v_linked,
      'already_linked', v_existing,
      'pending_registration', v_pending,
      'name_review', v_review,
      'invalid', v_invalid
    )
  );

  return jsonb_build_object(
    'items', v_items,
    'summary', jsonb_build_object(
      'total', jsonb_array_length(p_people),
      'linked', v_linked,
      'already_linked', v_existing,
      'pending_registration', v_pending,
      'name_review', v_review,
      'invalid', v_invalid
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.partnership_assert_professional(p_permission text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, p_permission) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  return v_actor;
end;
$function$;

CREATE OR REPLACE FUNCTION private.partnership_audit(p_action text, p_entity_name text, p_entity_id text, p_origin text, p_actor_user_id uuid, p_actor_patient_id bigint, p_old_values jsonb, p_new_values jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_passport text;
begin
  if p_origin not in ('professional', 'partnership_responsible', 'system') then
    raise exception 'Origem de auditoria inválida.';
  end if;

  if p_origin = 'professional' then
    select profile.passport into v_passport
    from public.profiles profile where profile.user_id = p_actor_user_id;
  elsif p_origin = 'partnership_responsible' then
    select patient.passport into v_passport
    from public.patients patient where patient.id = p_actor_patient_id;
  end if;

  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
  ) values (
    case when p_origin = 'professional' then p_actor_user_id else null end,
    v_passport,
    p_action,
    p_entity_name,
    p_entity_id,
    p_old_values,
    coalesce(p_new_values, '{}'::jsonb) || jsonb_build_object('origin', p_origin)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.partnership_name_key(p_value text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select regexp_replace(
    lower(translate(btrim(coalesce(p_value, '')),
      'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
      'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN')),
    '[^a-z0-9]+', ' ', 'g'
  );
$function$;

CREATE OR REPLACE FUNCTION private.partnership_patient_can_use_portal(p_patient_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.patients patient
    where patient.id = p_patient_id
      and patient.birth_date is not null
      and patient.passport ~ '^[0-9]{1,4}$'
  );
$function$;

CREATE OR REPLACE FUNCTION private.partnership_portal_actor(p_token_hash text, p_partnership_id bigint, p_require_active boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_patient_id bigint;
  v_status text;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Sessão do Portal inválida.' using errcode = '42501';
  end if;

  select session.patient_id, partnership.status
  into v_patient_id, v_status
  from private.patient_portal_session_record(p_token_hash) session
  join public.partnerships partnership
    on partnership.id = p_partnership_id
   and partnership.responsible_patient_id = session.patient_id;

  if not found then
    raise exception 'Parceria não localizada para esta sessão.' using errcode = '42501';
  end if;
  if p_require_active and v_status <> 'active' then
    raise exception 'Esta parceria está inativa e não permite alterações.' using errcode = '22023';
  end if;

  return v_patient_id;
end;
$function$;

CREATE OR REPLACE FUNCTION private.patient_portal_attendance_metrics(p_patient_id bigint)
 RETURNS TABLE(total_attendances integer, lifetime_spent numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    count(*)::integer,
    coalesce(sum(attendance.total), 0)::numeric(18, 2)
  from public.attendances attendance
  where attendance.patient_id = p_patient_id
    and attendance.status = 'completed';
$function$;


CREATE OR REPLACE FUNCTION private.patient_portal_session_record(p_token_hash text)
 RETURNS TABLE(patient_id bigint, patient_name text, patient_passport text, expires_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    session.patient_id,
    patient.name,
    patient.passport,
    session.expires_at
  from public.patient_portal_sessions session
  join public.patients patient on patient.id = session.patient_id
  where session.token_hash = p_token_hash
    and session.revoked_at is null
    and session.expires_at > clock_timestamp()
  limit 1;
$function$;

CREATE OR REPLACE FUNCTION private.prevent_clinical_report_meta_language()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_report_text text;
begin
  if new.status not in ('awaiting_review', 'completed') then return new; end if;
  v_report_text := concat_ws(
    ' ',
    new.technique,
    new.findings,
    new.conclusion,
    new.result_data->>'notes'
  );
  if private.clinical_text_contains_meta_language(v_report_text) then
    raise exception 'O laudo contém referência indevida ao contexto do sistema. Corrija ou gere novamente.';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.protect_completed_clinical_exam()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if old.status = 'completed' then
    raise exception 'Exames concluídos são imutáveis no fluxo normal.';
  end if;
  if new.status = 'completed' and old.status <> 'awaiting_review' then
    raise exception 'A conclusão exige revisão prévia.';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.protect_exam_ai_generation_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.id is distinct from old.id or new.exam_id is distinct from old.exam_id
     or new.generation_type is distinct from old.generation_type or new.requested_by is distinct from old.requested_by
     or new.model is distinct from old.model or new.reasoning_effort is distinct from old.reasoning_effort
     or new.prompt_version is distinct from old.prompt_version or new.source_exam_updated_at is distinct from old.source_exam_updated_at
     or new.source_image_generation_id is distinct from old.source_image_generation_id
     or new.source_image_id is distinct from old.source_image_id
     or new.idempotency_key is distinct from old.idempotency_key or new.created_at is distinct from old.created_at
     or (old.status <> 'requested' and (new.image_quality is distinct from old.image_quality or new.image_size is distinct from old.image_size
       or new.image_count is distinct from old.image_count or new.draft_storage_path is distinct from old.draft_storage_path
       or new.draft_mime_type is distinct from old.draft_mime_type or new.draft_file_size is distinct from old.draft_file_size))
     or (old.status <> 'completed' and new.official_image_id is distinct from old.official_image_id) then
    raise exception 'Os metadados da geração de IA são imutáveis.';
  end if;
  if not ((old.status = 'requested' and new.status in ('completed', 'failed')) or (old.status = 'completed' and new.status in ('applied', 'discarded'))) then
    raise exception 'Transição inválida da geração de IA.';
  end if;
  new.updated_at := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.provision_professional_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_registration_date date := (new.created_at at time zone 'America/Sao_Paulo')::date;
begin
  insert into public.professional_identities (user_id, crm_code, registration_date)
  values (new.user_id, private.hpsm_build_internal_crm(new.passport, v_registration_date), v_registration_date)
  on conflict (user_id) do nothing;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.record_initial_staff_position()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.position_id is not null then
    insert into public.staff_position_history (
      employee_id, from_position_id, to_position_id, event_type, decided_by, effective_at, note
    ) values (
      new.user_id, null, new.position_id, 'initial_assignment',
      coalesce(new.created_by, new.user_id), new.created_at, 'Ingresso na hierarquia oficial.'
    );
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.resolve_flow_notifications(p_source_type text, p_source_id text, p_actor_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_count integer;
begin
  update public.notifications
  set resolved_at = coalesce(resolved_at, now()),
      resolved_by = coalesce(resolved_by, p_actor_id)
  where source_type = p_source_type
    and source_id = p_source_id
    and resolved_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION private.resolve_partnership_pending_for_patient()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pending record;
  v_membership_id bigint;
begin
  for v_pending in
    select pending.*
    from public.partnership_pending_beneficiaries pending
    where pending.passport = new.passport
      and pending.status = 'pending_registration'
    order by pending.id
    for update
  loop
    if private.partnership_name_key(v_pending.informed_name) <> private.partnership_name_key(new.name) then
      update public.partnership_pending_beneficiaries set status = 'name_review'
      where id = v_pending.id;
      perform private.partnership_audit('PARTNERSHIP_PENDING_NAME_REVIEW_REQUIRED', 'partnership_pending_beneficiaries', v_pending.id::text,
        'system', null, null, null,
        jsonb_build_object('partnership_id', v_pending.partnership_id, 'passport', new.passport));
      continue;
    end if;

    insert into public.patient_partnerships (patient_id, partnership_id, linked_by_type)
    values (new.id, v_pending.partnership_id, 'system')
    on conflict (partnership_id, patient_id) where status = 'active' do nothing
    returning id into v_membership_id;
    update public.partnership_pending_beneficiaries
    set status = 'resolved', resolved_at = now(), resolved_patient_id = new.id
    where id = v_pending.id;
    perform private.partnership_audit('PARTNERSHIP_PENDING_RESOLVED', 'partnership_pending_beneficiaries', v_pending.id::text,
      'system', null, null, null,
      jsonb_build_object('partnership_id', v_pending.partnership_id, 'patient_id', new.id, 'passport', new.passport));
  end loop;
  return new;
end;
$function$;


CREATE OR REPLACE FUNCTION private.staff_worked_minutes_since(p_employee_id uuid, p_since timestamp with time zone)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with bounds as (
    select
      p_since::date as since_date,
      (now() at time zone 'America/Sao_Paulo')::date as through_date
  ), months as (
    select month_start::date
    from bounds,
      lateral generate_series(
        date_trunc('month', bounds.since_date)::date,
        date_trunc('month', bounds.through_date)::date,
        interval '1 month'
      ) as month_start
  ), periods as (
    select
      months.month_start,
      greatest(months.month_start, bounds.since_date) as period_start,
      least((months.month_start + interval '1 month - 1 day')::date, bounds.through_date) as period_end
    from months cross join bounds
  ), readings as (
    select
      periods.month_start,
      periods.period_start,
      end_reading.total_minutes as end_total,
      case
        when periods.period_start = periods.month_start then 0
        else baseline.total_minutes
      end as baseline_total
    from periods
    left join lateral (
      select snapshot.total_minutes
      from public.rh_hour_snapshots snapshot
      where snapshot.employee_id = p_employee_id
        and snapshot.reference_month = periods.month_start
        and snapshot.reading_date <= periods.period_end
      order by snapshot.reading_date desc, snapshot.updated_at desc
      limit 1
    ) end_reading on true
    left join lateral (
      select snapshot.total_minutes
      from public.rh_hour_snapshots snapshot
      where snapshot.employee_id = p_employee_id
        and snapshot.reference_month = periods.month_start
        and snapshot.reading_date < periods.period_start
      order by snapshot.reading_date desc, snapshot.updated_at desc
      limit 1
    ) baseline on periods.period_start <> periods.month_start
  )
  select coalesce(sum(
    case
      when end_total is null or baseline_total is null then 0
      else greatest(0, end_total - baseline_total)
    end
  ), 0)::integer
  from readings;
$function$;

CREATE OR REPLACE FUNCTION private.submit_clinical_exam_review_as(p_exam_id bigint, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_missing text;
  v_missing_report text[] := array[]::text[];
  v_report_config jsonb;
  v_version integer;
  v_note text;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if p_actor is null or v_old.responsible_professional_id is distinct from p_actor or not private.has_permission(p_actor, 'exams.perform') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_old.status <> 'in_progress' then raise exception 'Este exame foi atualizado por outro profissional. Recarregue os dados para continuar.'; end if;

  v_report_config := coalesce(v_old.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_old.exam_type_id));
  if coalesce((v_report_config#>>'{fields,technique,required}')::boolean, false) and v_old.technique is null then v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,technique,label}'); end if;
  if coalesce((v_report_config#>>'{fields,findings,required}')::boolean, false) and v_old.findings is null then v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,findings,label}'); end if;
  if coalesce((v_report_config#>>'{fields,conclusion,required}')::boolean, false) and v_old.conclusion is null then v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,conclusion,label}'); end if;
  if coalesce((v_report_config#>>'{fields,observations,required}')::boolean, false) and nullif(btrim(v_old.result_data->>'notes'), '') is null then v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,observations,label}'); end if;
  if cardinality(v_missing_report) > 0 then raise exception 'Preencha os campos obrigatórios do laudo: %.', array_to_string(v_missing_report, ', '); end if;

  if v_old.result_data->>'schema' = 'hpsm.lab_result.v1' then
    select string_agg(snapshot->>'label', ', ' order by (snapshot->>'sort_order')::integer) into v_missing
    from jsonb_array_elements(v_old.result_data#>'{template_snapshot,parameters}') snapshot
    where (snapshot->>'active')::boolean and (snapshot->>'required')::boolean
      and not exists (select 1 from jsonb_array_elements(v_old.result_data->'parameters') result_parameter where result_parameter->>'key' = snapshot->>'key' and nullif(btrim(result_parameter->>'value'), '') is not null);
    if v_missing is not null then raise exception 'Preencha os parâmetros obrigatórios: %.', v_missing; end if;
  elsif v_old.result_data->>'schema' = 'hpsm.image_result.v1' then
    if (v_old.result_data#>>'{template_snapshot,region,required}')::boolean and nullif(btrim(v_old.result_data->>'region'), '') is null then raise exception 'Selecione a região examinada.'; end if;
    if v_old.result_data->>'region' = 'Outra região' and nullif(btrim(v_old.result_data->>'other_region'), '') is null then raise exception 'Informe a outra região examinada.'; end if;
    if (v_old.result_data#>>'{template_snapshot,supports_laterality}')::boolean and nullif(v_old.result_data->>'laterality', '') is null then raise exception 'Selecione a lateralidade.'; end if;
    if (v_old.result_data#>>'{template_snapshot,supports_contrast}')::boolean and nullif(v_old.result_data->>'contrast', '') is null then raise exception 'Informe o uso de contraste.'; end if;
    if (v_old.result_data#>>'{template_snapshot,requires_image}')::boolean and not exists (select 1 from public.clinical_exam_images image where image.exam_id = p_exam_id and image.removed_at is null) then raise exception 'Gere a imagem por IA antes do envio.'; end if;
  end if;

  v_note := case when exists (select 1 from public.clinical_exam_status_history history where history.exam_id = p_exam_id and history.to_status = 'awaiting_review') then 'Exame corrigido e reenviado para revisão.' else 'Exame gerado por IA e enviado para revisão humana.' end;
  update public.clinical_exams set status = 'awaiting_review', submitted_for_review_at = now(), correction_reason = null where id = p_exam_id returning * into v_new;
  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note) values (p_exam_id, 'in_progress', 'awaiting_review', p_actor, v_note);
  select coalesce(max(version.version_number), 0) + 1 into v_version from public.clinical_exam_report_versions version where version.exam_id = p_exam_id;
  insert into public.clinical_exam_report_versions (exam_id, version_number, snapshot, submitted_by, submitted_at)
  values (p_exam_id, v_version, private.build_clinical_exam_report_snapshot(p_exam_id), p_actor, v_new.submitted_for_review_at);
  perform private.audit_exam_action(p_actor, 'clinical_exam.submitted_for_review', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
end;
$function$;

CREATE OR REPLACE FUNCTION private.touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.validate_clinical_cast_link()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.attendance_id is not null and not exists (
    select 1
    from public.attendances attendance
    where attendance.id = new.attendance_id
      and attendance.patient_id = new.patient_id
      and attendance.status = 'completed'
  ) then
    raise exception 'O atendimento informado não pertence ao paciente ou não está concluído.';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.validate_clinical_exam_link()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.attendance_id is not null and not exists (
    select 1
    from public.attendances attendance
    where attendance.id = new.attendance_id
      and attendance.patient_id = new.patient_id
      and attendance.status = 'completed'
  ) then
    raise exception 'O atendimento informado não pertence ao paciente ou não está concluído.';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.validate_exam_ai_suggestion(p_exam_id bigint, p_generation_type text, p_payload jsonb)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.validate_exam_ai_suggestion_clinical_v4(p_exam_id, p_generation_type, p_payload);
  if private.exam_ai_payload_contains_meta_language(p_payload) then
    raise exception 'O conteúdo gerado contém referência indevida ao contexto do sistema. Nada foi aplicado.';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION private.validate_exam_ai_suggestion_clinical_v4(p_exam_id bigint, p_generation_type text, p_payload jsonb)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_exam public.clinical_exams;
  v_candidate jsonb;
  v_report jsonb;
  v_report_text text;
begin
  if p_generation_type <> 'generate_exam' then
    perform private.validate_exam_ai_suggestion_legacy_v3(p_exam_id, p_generation_type, p_payload);
    return;
  end if;
  select * into v_exam from public.clinical_exams where id = p_exam_id;
  if v_exam.id is null or v_exam.status <> 'in_progress' then raise exception 'O exame não aceita mais sugestões de IA.'; end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' or p_payload->>'schema' <> 'hpsm.ai.exam_bundle.v4'
     or coalesce(jsonb_typeof(p_payload->'parameters'), '') <> 'array'
     or coalesce(jsonb_typeof(p_payload->'report'), '') <> 'object'
     or exists (select 1 from jsonb_object_keys(p_payload) key where key not in ('schema', 'parameters', 'report')) then
    raise exception 'Exame completo gerado por IA inválido.';
  end if;
  if v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then raise exception 'Exames de imagem usam a geração visual completa.'; end if;

  v_report := p_payload->'report';
  if exists (select 1 from jsonb_object_keys(v_report) key where key not in ('technique', 'findings', 'conclusion', 'conduct'))
     or coalesce(jsonb_typeof(v_report->'technique'), '') <> 'string'
     or coalesce(jsonb_typeof(v_report->'findings'), '') <> 'array'
     or coalesce(jsonb_typeof(v_report->'conclusion'), '') <> 'string'
     or coalesce(jsonb_typeof(v_report->'conduct'), '') <> 'string'
     or jsonb_array_length(v_report->'findings') not between 1 and 4
     or char_length(btrim(v_report->>'technique')) not between 1 and 600
     or char_length(btrim(v_report->>'conclusion')) not between 1 and 1000
     or char_length(btrim(v_report->>'conduct')) not between 1 and 1200
     or exists (select 1 from jsonb_array_elements(v_report->'findings') item where jsonb_typeof(item) <> 'string' or char_length(btrim(item#>>'{}')) not between 1 and 1200) then
    raise exception 'Laudo completo gerado por IA fora dos limites permitidos.';
  end if;
  select lower(concat_ws(' ', v_report->>'technique', v_report->>'conclusion', v_report->>'conduct', string_agg(item, ' ')))
  into v_report_text from jsonb_array_elements_text(v_report->'findings') item;
  if v_report_text ~ '(sugest|possível|possivelmente|provavelmente|pode[[:space:]]+(ser|representar|indicar)|recomenda-se[[:space:]]+avaliação[[:space:]]+profissional|procure[[:space:]]+um[[:space:]]+médico|necessita[[:space:]]+avaliação[[:space:]]+especializada)' then
    raise exception 'O laudo deve declarar diretamente os achados do exame fictício.';
  end if;

  if v_exam.result_data->>'schema' = 'hpsm.lab_result.v1' then
    if jsonb_array_length(p_payload->'parameters') <> (
         select count(*) from jsonb_array_elements(v_exam.result_data#>'{template_snapshot,parameters}') parameter
         where coalesce((parameter->>'active')::boolean, false)
       )
       or (select count(*) <> count(distinct parameter->>'key') from jsonb_array_elements(p_payload->'parameters') parameter)
       or exists (
         select 1 from jsonb_array_elements(v_exam.result_data#>'{template_snapshot,parameters}') snapshot
         where coalesce((snapshot->>'active')::boolean, false) and not exists (
           select 1 from jsonb_array_elements(p_payload->'parameters') suggestion
           where suggestion->>'key' = snapshot->>'key' and nullif(btrim(suggestion->>'value'), '') is not null
         )
       ) then raise exception 'Resultados gerados incompatíveis com o template laboratorial.'; end if;
    v_candidate := v_exam.result_data || jsonb_build_object('parameters', p_payload->'parameters', 'notes', left(v_report->>'conduct', 12000));
    perform private.normalize_lab_result(v_exam.result_data, v_candidate);
  elsif jsonb_array_length(p_payload->'parameters') <> 0 then
    raise exception 'Este exame não utiliza parâmetros laboratoriais.';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION private.validate_exam_ai_suggestion_legacy_v3(p_exam_id bigint, p_generation_type text, p_payload jsonb)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_exam public.clinical_exams;
  v_candidate jsonb;
  v_config jsonb;
  v_report_text text;
begin
  select * into v_exam from public.clinical_exams where id = p_exam_id;
  if v_exam.id is null or v_exam.status <> 'in_progress' then raise exception 'O exame não aceita mais sugestões de IA.'; end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then raise exception 'Sugestão de IA inválida.'; end if;

  if p_generation_type = 'generate_lab_results' then
    if p_payload->>'schema' <> 'hpsm.ai.lab_suggestion.v1'
       or coalesce(jsonb_typeof(p_payload->'parameters'), '') <> 'array'
       or coalesce(jsonb_typeof(p_payload->'notes'), '') <> 'string'
       or exists (select 1 from jsonb_object_keys(p_payload) key where key not in ('schema', 'parameters', 'notes'))
       or jsonb_array_length(p_payload->'parameters') <> (
         select count(*) from jsonb_array_elements(v_exam.result_data#>'{template_snapshot,parameters}') parameter
         where coalesce((parameter->>'active')::boolean, false)
       )
       or (select count(*) <> count(distinct parameter->>'key') from jsonb_array_elements(p_payload->'parameters') parameter)
       or exists (
         select 1 from jsonb_array_elements(v_exam.result_data#>'{template_snapshot,parameters}') snapshot
         where coalesce((snapshot->>'active')::boolean, false)
           and not exists (select 1 from jsonb_array_elements(p_payload->'parameters') suggestion where suggestion->>'key' = snapshot->>'key')
       ) then raise exception 'Sugestão laboratorial incompatível com o template.'; end if;
    v_candidate := v_exam.result_data || jsonb_build_object('parameters', p_payload->'parameters', 'notes', left(p_payload->>'notes', 12000));
    perform private.normalize_lab_result(v_exam.result_data, v_candidate);
  elsif p_generation_type = 'generate_report' and p_payload->>'schema' = 'hpsm.ai.clinical_report.v3' then
    if exists (select 1 from jsonb_object_keys(p_payload) key where key not in ('schema', 'technique', 'findings', 'conclusion', 'conduct'))
       or coalesce(jsonb_typeof(p_payload->'technique'), '') <> 'string'
       or coalesce(jsonb_typeof(p_payload->'findings'), '') <> 'array'
       or coalesce(jsonb_typeof(p_payload->'conclusion'), '') <> 'string'
       or coalesce(jsonb_typeof(p_payload->'conduct'), '') <> 'string' then
      raise exception 'Laudo clínico gerado por IA inválido.';
    end if;
    if jsonb_array_length(p_payload->'findings') not between 1 and 4
       or char_length(btrim(p_payload->>'technique')) not between 1 and 600
       or char_length(btrim(p_payload->>'conclusion')) not between 1 and 1000
       or char_length(btrim(p_payload->>'conduct')) not between 1 and 1200
       or exists (
         select 1 from jsonb_array_elements(p_payload->'findings') item
         where jsonb_typeof(item) <> 'string' or char_length(btrim(item#>>'{}')) not between 1 and 1200
       ) then raise exception 'Laudo clínico gerado por IA fora dos limites permitidos.'; end if;
    select lower(concat_ws(' ', p_payload->>'technique', p_payload->>'conclusion', p_payload->>'conduct', string_agg(item, ' ')))
    into v_report_text from jsonb_array_elements_text(p_payload->'findings') item;
    if v_report_text ~ '(sugest|possível|possivelmente|provavelmente|pode[[:space:]]+(ser|representar|indicar)|recomenda-se[[:space:]]+avaliação[[:space:]]+profissional|procure[[:space:]]+um[[:space:]]+médico|necessita[[:space:]]+avaliação[[:space:]]+especializada)' then
      raise exception 'O laudo deve declarar diretamente os achados do exame fictício.';
    end if;
  elsif p_generation_type = 'generate_report' and p_payload->>'schema' in ('hpsm.ai.simple_report.v1', 'hpsm.ai.simple_report.v2') then
    if exists (
         select 1 from jsonb_object_keys(p_payload) key
         where key not in ('schema', 'summary', 'findings', 'conclusion', 'rp_note')
       )
       or coalesce(jsonb_typeof(p_payload->'summary'), '') <> 'string'
       or coalesce(jsonb_typeof(p_payload->'findings'), '') <> 'array'
       or coalesce(jsonb_typeof(p_payload->'conclusion'), '') <> 'string'
       or (p_payload->>'schema' = 'hpsm.ai.simple_report.v1' and coalesce(jsonb_typeof(p_payload->'rp_note'), '') <> 'string')
       or (p_payload->>'schema' = 'hpsm.ai.simple_report.v2' and p_payload ? 'rp_note')
       or jsonb_array_length(p_payload->'findings') not between 1 and 4
       or char_length(p_payload->>'summary') > 1200
       or char_length(p_payload->>'conclusion') > 1200
       or char_length(coalesce(p_payload->>'rp_note', '')) > 600
       or exists (select 1 from jsonb_array_elements(p_payload->'findings') item where jsonb_typeof(item) <> 'string' or char_length(item#>>'{}') > 1200)
    then raise exception 'Sugestão de laudo simplificado inválida.'; end if;
  elsif p_generation_type = 'generate_report' then
    v_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
    if p_payload->>'schema' <> 'hpsm.ai.report_suggestion.v1'
       or coalesce(jsonb_typeof(p_payload->'fields'), '') <> 'object'
       or exists (select 1 from jsonb_object_keys(p_payload) key where key not in ('schema', 'fields'))
       or exists (
         select 1 from jsonb_object_keys(p_payload->'fields') key
         where key not in ('technique', 'findings', 'conclusion', 'observations')
            or coalesce((v_config#>>array['fields', key, 'visible'])::boolean, false) is false
            or jsonb_typeof(p_payload->'fields'->key) <> 'string'
            or char_length(p_payload->'fields'->>key) > case key when 'findings' then 8000 when 'observations' then 12000 else 4000 end
       )
       or exists (
         select 1 from jsonb_object_keys(v_config->'fields') key
         where coalesce((v_config#>>array['fields', key, 'visible'])::boolean, false) and not (p_payload->'fields' ? key)
       ) then raise exception 'Sugestão de laudo incompatível com a configuração do exame.'; end if;
  else
    raise exception 'Operação de IA inválida.';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.annul_hr_warning(p_warning_id bigint, p_reason text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_warning public.rh_warnings;
  v_remaining integer;
  v_reactivated boolean := false;
begin
  if not private.has_permission(p_actor_id, 'hr.warnings.annul') then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode anular advertências.';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe o motivo da anulação entre 10 e 2000 caracteres.';
  end if;

  select * into v_warning from public.rh_warnings where id = p_warning_id for update;
  if not found or v_warning.status <> 'active' then
    raise exception using errcode = 'P0002', message = 'Advertência não encontrada ou já anulada.';
  end if;
  if v_warning.employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode anular a própria advertência.';
  end if;

  perform 1 from public.profiles where user_id = v_warning.employee_id for update;
  update public.rh_warnings
  set status = 'annulled', annulled_by = p_actor_id, annulled_at = now(),
      annulment_reason = btrim(p_reason), updated_at = now()
  where id = p_warning_id
  returning * into v_warning;

  if v_warning.weekly_record_id is not null then
    update public.rh_weekly_records
    set status = 'warning_annulled', updated_at = now()
    where id = v_warning.weekly_record_id;
  end if;

  select count(*)::integer into v_remaining
  from public.rh_warnings
  where employee_id = v_warning.employee_id
    and cycle_month = v_warning.cycle_month
    and status = 'active';

  if v_remaining < 3 and exists (
    select 1 from public.rh_disciplinary_reviews
    where employee_id = v_warning.employee_id
      and cycle_month = v_warning.cycle_month
      and status in ('pending', 'suspension_maintained')
  ) then
    update public.rh_disciplinary_reviews
    set status = 'reactivated', decided_by = p_actor_id, decided_at = now(),
        decision_note = btrim(p_reason), updated_at = now()
    where employee_id = v_warning.employee_id
      and cycle_month = v_warning.cycle_month
      and status in ('pending', 'suspension_maintained');

    update public.profiles
    set status = 'active', updated_by = p_actor_id, updated_at = now()
    where user_id = v_warning.employee_id and status = 'suspended';
    v_reactivated := true;
  end if;

  return jsonb_build_object(
    'warning', to_jsonb(v_warning),
    'active_warnings', v_remaining,
    'reactivated', v_reactivated
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.apply_and_submit_clinical_exam_ai_generation(p_generation_id uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
  v_parameters jsonb;
  v_candidate jsonb;
  v_result_data jsonb;
  v_config jsonb;
  v_report_values jsonb;
begin
  select * into v_generation from public.exam_ai_generations where id = p_generation_id;
  if v_generation.id is null then raise exception 'Geração de IA não localizada.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_generation.exam_id::text || ':complete_exam', 0));
  select * into v_exam from public.clinical_exams where id = v_generation.exam_id for update;
  select * into v_generation from public.exam_ai_generations where id = p_generation_id for update;
  if v_exam.status <> 'in_progress' or v_exam.responsible_professional_id is distinct from p_actor or not private.has_permission(p_actor, 'exams.perform') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_generation.generation_type <> 'generate_exam' or v_generation.status <> 'completed' or v_generation.requested_by is distinct from p_actor then raise exception 'Exame gerado por IA indisponível.'; end if;
  if v_exam.updated_at is distinct from v_generation.source_exam_updated_at then raise exception 'O exame foi atualizado durante a geração. Gere novamente.'; end if;
  perform private.validate_exam_ai_suggestion(v_exam.id, 'generate_exam', v_generation.suggestion_payload);

  v_report_values := private.clinical_exam_ai_report_values(v_generation.suggestion_payload);
  v_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
  if v_exam.result_data->>'schema' = 'hpsm.lab_result.v1' then
    select jsonb_agg(parameter || jsonb_build_object('value', suggestion.item->>'value', 'flag', suggestion.item->'flag') order by (parameter->>'sort_order')::integer, parameter->>'label') into v_parameters
    from jsonb_array_elements(v_exam.result_data->'parameters') parameter
    join lateral (select item from jsonb_array_elements(v_generation.suggestion_payload->'parameters') item where item->>'key' = parameter->>'key' limit 1) suggestion on true;
    v_candidate := v_exam.result_data || jsonb_build_object('parameters', v_parameters, 'notes', v_report_values->>'conduct');
    v_result_data := private.normalize_lab_result(v_exam.result_data, v_candidate)
      || jsonb_build_object('report_config_snapshot', v_exam.result_data->'report_config_snapshot', 'exam_type_snapshot', v_exam.result_data->'exam_type_snapshot');
  else
    v_result_data := jsonb_set(v_exam.result_data, '{notes}', to_jsonb(v_report_values->>'conduct'), true);
  end if;

  update public.clinical_exams set
    technique = case when coalesce((v_config#>>'{fields,technique,visible}')::boolean, false) then v_report_values->>'technique' else technique end,
    findings = case when coalesce((v_config#>>'{fields,findings,visible}')::boolean, false) then v_report_values->>'findings' else findings end,
    conclusion = case when coalesce((v_config#>>'{fields,conclusion,visible}')::boolean, false) then v_report_values->>'conclusion' else conclusion end,
    result_data = v_result_data
  where id = v_exam.id;
  update public.exam_ai_generations set status = 'applied', applied_at = now() where id = p_generation_id;
  perform private.audit_exam_action(p_actor, 'clinical_exam.ai_complete_exam_applied', 'exam_ai_generations', p_generation_id::text,
    jsonb_build_object('status', 'completed'), jsonb_build_object('status', 'applied', 'exam_id', v_exam.id, 'model', v_generation.model, 'prompt_version', v_generation.prompt_version));
  perform private.submit_clinical_exam_review_as(v_exam.id, p_actor);
  return jsonb_build_object('exam_id', v_exam.id, 'status', 'awaiting_review');
end;
$function$;

CREATE OR REPLACE FUNCTION public.apply_clinical_exam_ai_bundle(p_image_generation_id uuid, p_report_generation_id uuid, p_actor uuid, p_image_id uuid, p_storage_path text, p_file_size bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_image_generation public.exam_ai_generations;
  v_report_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
  v_count integer;
  v_config jsonb;
  v_report_values jsonb;
  v_result_data jsonb;
begin
  select * into v_image_generation from public.exam_ai_generations where id = p_image_generation_id;
  select * into v_report_generation from public.exam_ai_generations where id = p_report_generation_id;
  if v_image_generation.id is null or v_report_generation.id is null or v_image_generation.exam_id <> v_report_generation.exam_id then raise exception 'Geração de IA incompleta.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_image_generation.exam_id::text || ':ai_bundle', 0));
  select * into v_exam from public.clinical_exams where id = v_image_generation.exam_id for update;
  select * into v_image_generation from public.exam_ai_generations where id = p_image_generation_id for update;
  select * into v_report_generation from public.exam_ai_generations where id = p_report_generation_id for update;
  if v_exam.status <> 'in_progress' or v_exam.responsible_professional_id is distinct from p_actor or not private.has_permission(p_actor, 'exams.perform') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_image_generation.generation_type <> 'generate_image' or v_image_generation.status <> 'completed' or v_image_generation.requested_by is distinct from p_actor then raise exception 'Rascunho de imagem indisponível.'; end if;
  if v_report_generation.generation_type <> 'generate_report' or v_report_generation.status <> 'completed' then raise exception 'Laudo gerado por IA indisponível.'; end if;
  if v_report_generation.source_image_generation_id is distinct from p_image_generation_id then raise exception 'O laudo não corresponde à imagem gerada.'; end if;
  if v_exam.updated_at is distinct from v_report_generation.source_exam_updated_at then raise exception 'O exame foi atualizado durante a geração. Gere novamente.'; end if;
  if p_storage_path <> 'clinical-exams/' || v_exam.id::text || '/' || p_image_id::text || '.png' or p_file_size <> v_image_generation.draft_file_size then raise exception 'Imagem final inválida.'; end if;
  perform private.validate_exam_ai_suggestion(v_exam.id, 'generate_report', v_report_generation.suggestion_payload);

  select count(*) into v_count from public.clinical_exam_images where exam_id = v_exam.id and removed_at is null;
  if not (v_exam.result_data#>>'{template_snapshot,allows_multiple_images}')::boolean and v_count > 0 then raise exception 'Este tipo de exame aceita somente uma imagem.'; end if;
  insert into public.clinical_exam_images(id, exam_id, storage_path, original_filename, mime_type, file_size, sort_order, caption, source, uploaded_by)
  values(p_image_id, v_exam.id, p_storage_path, 'imagem-ficticia-ia.png', 'image/png', p_file_size, (v_count + 1) * 10, 'Imagem fictícia gerada por IA para fins de RP.', 'ai_generated', p_actor);

  v_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
  v_report_values := private.clinical_exam_ai_report_values(v_report_generation.suggestion_payload);
  v_result_data := jsonb_set(v_exam.result_data, '{notes}', to_jsonb(v_report_values->>'conduct'), true);
  update public.clinical_exams set
    technique = case when coalesce((v_config#>>'{fields,technique,visible}')::boolean, false) then v_report_values->>'technique' else technique end,
    findings = case when coalesce((v_config#>>'{fields,findings,visible}')::boolean, false) then v_report_values->>'findings' else findings end,
    conclusion = case when coalesce((v_config#>>'{fields,conclusion,visible}')::boolean, false) then v_report_values->>'conclusion' else conclusion end,
    result_data = v_result_data
  where id = v_exam.id;
  update public.exam_ai_generations set status = 'applied', applied_at = now(), official_image_id = p_image_id where id = p_image_generation_id;
  update public.exam_ai_generations set status = 'applied', applied_at = now() where id = p_report_generation_id;
  perform private.audit_exam_action(p_actor, 'clinical_exam.ai_bundle_applied', 'clinical_exams', v_exam.id::text, null,
    jsonb_build_object('image_generation_id', p_image_generation_id, 'report_generation_id', p_report_generation_id, 'image_id', p_image_id,
      'image_model', v_image_generation.model, 'report_model', v_report_generation.model, 'report_prompt_version', v_report_generation.prompt_version));
  perform private.submit_clinical_exam_review_as(v_exam.id, p_actor);
  return jsonb_build_object('exam_id', v_exam.id, 'image_id', p_image_id, 'status', 'awaiting_review', 'draft_path', v_image_generation.draft_storage_path);
end;
$function$;

CREATE OR REPLACE FUNCTION public.apply_clinical_exam_ai_generation(p_generation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
  v_parameters jsonb;
  v_candidate jsonb;
  v_result_data jsonb;
  v_config jsonb;
  v_report_values jsonb;
  v_technique text;
  v_findings text;
  v_conclusion text;
  v_conduct text;
begin
  select * into v_generation from public.exam_ai_generations where id = p_generation_id;
  if v_generation.id is null then raise exception 'Sugestão de IA não localizada.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_generation.exam_id::text || ':' || v_generation.generation_type, 0));
  select * into v_exam from public.clinical_exams where id = v_generation.exam_id for update;
  select * into v_generation from public.exam_ai_generations where id = p_generation_id for update;
  if v_exam.status <> 'in_progress' then raise exception 'O exame não aceita mais alterações.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, v_exam.id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_generation.status <> 'completed' then raise exception 'A sugestão de IA não está disponível para aplicação.'; end if;
  if v_exam.updated_at is distinct from v_generation.source_exam_updated_at then raise exception 'O exame foi atualizado após a geração. Gere uma nova sugestão para comparar com o rascunho atual.'; end if;
  perform private.validate_exam_ai_suggestion(v_exam.id, v_generation.generation_type, v_generation.suggestion_payload);

  if v_generation.generation_type = 'generate_lab_results' then
    select jsonb_agg(parameter || jsonb_build_object('value', suggestion.item->>'value', 'flag', suggestion.item->'flag')
      order by (parameter->>'sort_order')::integer, parameter->>'label') into v_parameters
    from jsonb_array_elements(v_exam.result_data->'parameters') parameter
    join lateral (select item from jsonb_array_elements(v_generation.suggestion_payload->'parameters') item where item->>'key' = parameter->>'key' limit 1) suggestion on true;
    v_candidate := v_exam.result_data || jsonb_build_object('parameters', v_parameters, 'notes', v_generation.suggestion_payload->>'notes');
    v_result_data := private.normalize_lab_result(v_exam.result_data, v_candidate)
      || jsonb_build_object('report_config_snapshot', v_exam.result_data->'report_config_snapshot', 'exam_type_snapshot', v_exam.result_data->'exam_type_snapshot');
    update public.clinical_exams set result_data = v_result_data where id = v_exam.id;
  else
    v_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
    v_report_values := private.clinical_exam_ai_report_values(v_generation.suggestion_payload);
    v_technique := v_report_values->>'technique';
    v_findings := v_report_values->>'findings';
    v_conclusion := v_report_values->>'conclusion';
    v_conduct := v_report_values->>'conduct';
    v_result_data := case
      when v_generation.suggestion_payload->>'schema' = 'hpsm.ai.clinical_report.v3'
        then jsonb_set(v_exam.result_data, '{notes}', to_jsonb(v_conduct), true)
      when v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then v_exam.result_data
      when v_conduct is not null and coalesce((v_config#>>'{fields,observations,visible}')::boolean, false)
        then jsonb_set(v_exam.result_data, '{notes}', to_jsonb(v_conduct), true)
      else v_exam.result_data
    end;
    update public.clinical_exams set
      technique = case when coalesce((v_config#>>'{fields,technique,visible}')::boolean, false) then v_technique else technique end,
      findings = case when coalesce((v_config#>>'{fields,findings,visible}')::boolean, false) then v_findings else findings end,
      conclusion = case when coalesce((v_config#>>'{fields,conclusion,visible}')::boolean, false) then v_conclusion else conclusion end,
      result_data = v_result_data
    where id = v_exam.id;
  end if;

  update public.exam_ai_generations set status = 'applied', applied_at = now() where id = p_generation_id;
  perform private.audit_exam_action(v_actor, 'clinical_exam.ai_applied', 'exam_ai_generations', p_generation_id::text,
    jsonb_build_object('status', 'completed'),
    jsonb_build_object('status', 'applied', 'exam_id', v_exam.id, 'generation_type', v_generation.generation_type,
      'model', v_generation.model, 'prompt_version', v_generation.prompt_version,
      'source_image_generation_id', v_generation.source_image_generation_id, 'source_image_id', v_generation.source_image_id));
end;
$function$;

CREATE OR REPLACE FUNCTION public.apply_clinical_exam_ai_image(p_generation_id uuid, p_actor uuid, p_image_id uuid, p_storage_path text, p_file_size bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_generation public.exam_ai_generations; v_exam public.clinical_exams; v_count integer; v_image public.clinical_exam_images;
begin
  select * into v_generation from public.exam_ai_generations where id=p_generation_id for update;
  if v_generation.id is null or v_generation.generation_type<>'generate_image' or v_generation.status<>'completed' then raise exception 'Rascunho de imagem indisponível.'; end if;
  select * into v_exam from public.clinical_exams where id=v_generation.exam_id for update;
  if v_exam.status<>'in_progress' or v_exam.responsible_professional_id is distinct from p_actor or not private.has_permission(p_actor,'exams.perform') then raise exception 'Acesso não autorizado.' using errcode='42501'; end if;
  if p_actor is distinct from v_generation.requested_by then raise exception 'Somente o solicitante pode aplicar este rascunho.'; end if;
  if p_storage_path <> 'clinical-exams/'||v_exam.id::text||'/'||p_image_id::text||'.png' or p_file_size<>v_generation.draft_file_size then raise exception 'Imagem final inválida.'; end if;
  select count(*) into v_count from public.clinical_exam_images where exam_id=v_exam.id and removed_at is null;
  if not (v_exam.result_data#>>'{template_snapshot,allows_multiple_images}')::boolean and v_count>0 then raise exception 'Este tipo de exame aceita somente uma imagem.'; end if;
  insert into public.clinical_exam_images(id,exam_id,storage_path,original_filename,mime_type,file_size,sort_order,caption,source,uploaded_by)
  values(p_image_id,v_exam.id,p_storage_path,'imagem-ficticia-ia.png','image/png',p_file_size,(v_count+1)*10,'Imagem fictícia gerada por IA para fins de RP.','ai_generated',p_actor) returning * into v_image;
  update public.exam_ai_generations set status='applied',applied_at=now(),official_image_id=p_image_id where id=p_generation_id;
  update public.clinical_exams set updated_at=now() where id=v_exam.id;
  perform private.audit_exam_action(p_actor,'clinical_exam.ai_image_applied','clinical_exam_images',p_image_id::text,null,jsonb_build_object('exam_id',v_exam.id,'source','ai_generated','generation_id',p_generation_id));
  return jsonb_build_object('image_id',p_image_id,'draft_path',v_generation.draft_storage_path);
end; $function$;

CREATE OR REPLACE FUNCTION public.appoint_staff_position(p_employee_id uuid, p_to_position_id bigint, p_note text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_level smallint;
  v_employee public.profiles;
  v_from public.staff_positions;
  v_to public.staff_positions;
  v_old_general uuid;
  v_level_13_id bigint;
  v_history public.staff_position_history;
begin
  v_actor_level := private.current_position_level(p_actor_id);
  select * into v_employee from public.profiles where user_id = p_employee_id for update;
  select * into v_from from public.staff_positions where id = v_employee.position_id;
  select * into v_to from public.staff_positions where id = p_to_position_id and active;
  if not found or v_employee.status = 'inactive' or v_from.level + 1 <> v_to.level or v_to.level < 11 then
    raise exception using errcode = '22023', message = 'A nomeação deve avançar somente um cargo na hierarquia.';
  end if;
  if char_length(btrim(coalesce(p_note, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe a fundamentação da nomeação.';
  end if;
  if v_to.level in (11, 12) and not (
      private.has_permission(p_actor_id, 'appointments.manage') and v_actor_level >= 13
    ) then
    raise exception using errcode = '42501', message = 'Somente os níveis 13 e 14 podem realizar esta nomeação.';
  elsif v_to.level = 13 and not (
      private.has_permission(p_actor_id, 'appointments.manage') and v_actor_level = 14
    ) then
    raise exception using errcode = '42501', message = 'Somente o Diretor Geral pode nomear o Diretor Clínico.';
  elsif v_to.level = 14 then
    if not (private.has_permission(p_actor_id, 'succession.manage') and v_actor_level = 14 and p_actor_id <> p_employee_id) then
      raise exception using errcode = '42501', message = 'A sucessão é exclusiva do Diretor Geral e exige outro Diretor Clínico.';
    end if;
    select user_id into v_old_general from public.profiles where role_code = 'diretor_geral' for update;
    select id into v_level_13_id from public.staff_positions where level = 13;
    perform set_config('hpsm.position_change_authorized', 'true', true);
    update public.profiles
    set role_code = 'funcionario', position_id = v_level_13_id, updated_by = p_actor_id, updated_at = now()
    where user_id = v_old_general;
    insert into public.staff_position_history (
      employee_id, from_position_id, to_position_id, event_type, decided_by, note
    ) values (
      v_old_general, v_to.id, v_level_13_id, 'succession', p_actor_id,
      'Saída da Direção Geral. ' || btrim(p_note)
    );
    update public.profiles
    set role_code = 'diretor_geral', position_id = v_to.id, updated_by = p_actor_id, updated_at = now()
    where user_id = p_employee_id;
  else
    perform set_config('hpsm.position_change_authorized', 'true', true);
    update public.profiles
    set position_id = v_to.id, updated_by = p_actor_id, updated_at = now()
    where user_id = p_employee_id;
  end if;
  insert into public.staff_position_history (
    employee_id, from_position_id, to_position_id, event_type, decided_by, note
  ) values (
    p_employee_id, v_from.id, v_to.id,
    case when v_to.level = 14 then 'succession' else 'appointment' end,
    p_actor_id, btrim(p_note)
  ) returning * into v_history;
  insert into public.notifications (
    kind, recipient_id, priority, title, body, action_url, created_by
  ) values (
    'personal', p_employee_id, 'important', 'Novo cargo registrado',
    format('Sua nomeação para %s foi registrada.', v_to.name), '/meu-rh', p_actor_id
  );
  return to_jsonb(v_history);
end;
$function$;

CREATE OR REPLACE FUNCTION public.archive_notification_announcement(p_notification_id bigint, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_old public.notifications;
  v_row public.notifications;
  v_actor_passport text;
begin
  if not (private.is_director_user(p_actor_id) or private.has_permission(p_actor_id, 'communications.manage')) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode arquivar avisos.';
  end if;

  select * into v_old
  from public.notifications
  where id = p_notification_id
  for update;

  if not found or v_old.kind <> 'announcement' or v_old.archived_at is not null then
    raise exception using errcode = 'P0002', message = 'Aviso nao encontrado ou ja arquivado.';
  end if;

  update public.notifications
  set archived_at = now(), archived_by = p_actor_id
  where id = p_notification_id
  returning * into v_row;

  select passport into v_actor_passport
  from public.profiles
  where user_id = p_actor_id;

  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
  ) values (
    p_actor_id, v_actor_passport, 'UPDATE', 'notifications', v_row.id::text, to_jsonb(v_old), to_jsonb(v_row)
  );

  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.assign_initial_staff_position(p_employee_id uuid, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles;
  v_position public.staff_positions;
  v_history public.staff_position_history;
begin
  if not private.has_permission(p_actor_id, 'access.manage')
     or private.current_position_level(p_actor_id) <> 14 then
    raise exception using errcode = '42501', message = 'Somente o Diretor Geral pode definir o cargo inicial de perfis legados.';
  end if;
  select * into v_profile from public.profiles where user_id = p_employee_id for update;
  if not found or v_profile.status = 'inactive' or v_profile.position_id is not null then
    raise exception using errcode = '22023', message = 'Este perfil não está disponível para atribuição inicial.';
  end if;
  select * into v_position from public.staff_positions where level = 1 and active;
  perform set_config('hpsm.position_change_authorized', 'true', true);
  update public.profiles
  set position_id = v_position.id, role_code = 'funcionario', updated_by = p_actor_id, updated_at = now()
  where user_id = p_employee_id;
  insert into public.staff_position_history (
    employee_id, from_position_id, to_position_id, event_type, decided_by, effective_at, note
  ) values (
    p_employee_id, null, v_position.id, 'initial_assignment', p_actor_id,
    now(), 'Ingresso de perfil legado na hierarquia oficial.'
  ) returning * into v_history;
  insert into public.notifications (
    kind, recipient_id, priority, title, body, action_url, created_by
  ) values (
    'personal', p_employee_id, 'normal', 'Cargo inicial definido',
    'Seu cargo inicial foi registrado na hierarquia oficial.', '/meu-rh', p_actor_id
  );
  return to_jsonb(v_history);
end;
$function$;

CREATE OR REPLACE FUNCTION public.begin_clinical_exam_ai_generation(p_exam_id bigint, p_generation_type text, p_requested_by uuid, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_exam public.clinical_exams;
  v_generation public.exam_ai_generations;
  v_recent_count integer;
begin
  if p_requested_by is null or p_idempotency_key is null then raise exception 'Requisição de IA inválida.'; end if;
  if p_generation_type not in ('generate_lab_results', 'generate_report') then raise exception 'Operação de IA inválida.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_exam_id::text || ':' || p_generation_type, 0));

  select * into v_generation
  from public.exam_ai_generations generation
  where generation.idempotency_key = p_idempotency_key
  for update;

  if v_generation.id is not null then
    if v_generation.exam_id <> p_exam_id
       or v_generation.generation_type <> p_generation_type
       or v_generation.requested_by <> p_requested_by then
      raise exception 'Chave de idempotência inválida.';
    end if;
    return jsonb_build_object(
      'generation_id', v_generation.id,
      'status', v_generation.status,
      'suggestion', v_generation.suggestion_payload,
      'replayed', true
    );
  end if;

  select * into v_exam from public.clinical_exams where id = p_exam_id for update;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'in_progress' then raise exception 'A IA só pode auxiliar exames em execução.'; end if;
  if not private.can_access_clinical_exam_ai(p_requested_by, p_exam_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_generation_type = 'generate_lab_results' and v_exam.result_data->>'schema' <> 'hpsm.lab_result.v1' then
    raise exception 'A geração de resultados está disponível apenas para exames laboratoriais.';
  end if;

  select * into v_generation
  from public.exam_ai_generations generation
  where generation.exam_id = p_exam_id
    and generation.generation_type = p_generation_type
    and generation.status = 'requested'
  order by generation.created_at desc
  limit 1
  for update;

  if v_generation.id is not null and v_generation.created_at >= now() - interval '2 minutes' then
    return jsonb_build_object('generation_id', v_generation.id, 'status', 'requested', 'suggestion', null, 'replayed', true);
  elsif v_generation.id is not null then
    update public.exam_ai_generations
    set status = 'failed', failed_at = now(), error_code = 'stale_request'
    where id = v_generation.id;
  end if;

  select count(*)::integer into v_recent_count
  from public.exam_ai_generations generation
  where generation.requested_by = p_requested_by
    and generation.created_at >= now() - interval '10 minutes';
  if v_recent_count >= 6 then raise exception 'Limite temporário de gerações atingido. Aguarde alguns minutos.'; end if;

  insert into public.exam_ai_generations (
    exam_id, generation_type, requested_by, model, reasoning_effort, prompt_version, source_exam_updated_at, idempotency_key
  ) values (
    p_exam_id, p_generation_type, p_requested_by, 'gpt-5.6-luna', 'low', 'exam-rp-luna-v1', v_exam.updated_at, p_idempotency_key
  ) returning * into v_generation;

  perform private.audit_exam_action(
    p_requested_by,
    'clinical_exam.ai_requested',
    'exam_ai_generations',
    v_generation.id::text,
    null,
    jsonb_build_object('exam_id', p_exam_id, 'generation_type', p_generation_type, 'model', v_generation.model, 'prompt_version', v_generation.prompt_version)
  );

  return jsonb_build_object('generation_id', v_generation.id, 'status', v_generation.status, 'suggestion', null, 'replayed', false);
end;
$function$;

CREATE OR REPLACE FUNCTION public.begin_clinical_exam_ai_generation(p_exam_id bigint, p_generation_type text, p_requested_by uuid, p_idempotency_key uuid, p_source_image_generation_id uuid, p_source_image_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_exam public.clinical_exams;
  v_generation public.exam_ai_generations;
  v_recent_count integer;
  v_prompt_version text;
begin
  if p_requested_by is null or p_idempotency_key is null then raise exception 'Requisição de IA inválida.'; end if;
  if p_generation_type not in ('generate_lab_results', 'generate_report', 'generate_exam') then raise exception 'Operação de IA inválida.'; end if;
  if p_source_image_generation_id is not null and p_source_image_id is not null then raise exception 'Referência de imagem inválida.'; end if;
  if p_generation_type <> 'generate_report' and (p_source_image_generation_id is not null or p_source_image_id is not null) then raise exception 'Esta operação não aceita imagem.'; end if;
  v_prompt_version := case when p_generation_type = 'generate_exam' then 'exam-rp-luna-v4' else 'exam-rp-luna-v3' end;

  perform pg_advisory_xact_lock(hashtextextended(p_exam_id::text || ':' || p_generation_type, 0));
  select * into v_generation from public.exam_ai_generations where idempotency_key = p_idempotency_key for update;
  if v_generation.id is not null then
    if v_generation.exam_id <> p_exam_id or v_generation.generation_type <> p_generation_type or v_generation.requested_by <> p_requested_by
       or v_generation.source_image_generation_id is distinct from p_source_image_generation_id
       or v_generation.source_image_id is distinct from p_source_image_id then raise exception 'Chave de idempotência inválida.'; end if;
    return jsonb_build_object('generation_id', v_generation.id, 'status', v_generation.status, 'suggestion', v_generation.suggestion_payload, 'replayed', true);
  end if;

  select * into v_exam from public.clinical_exams where id = p_exam_id for update;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'in_progress' then raise exception 'A IA só pode auxiliar exames em execução.'; end if;
  if not private.can_access_clinical_exam_ai(p_requested_by, p_exam_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if p_generation_type = 'generate_lab_results' and v_exam.result_data->>'schema' <> 'hpsm.lab_result.v1' then raise exception 'A geração de resultados está disponível apenas para exames laboratoriais.'; end if;
  if p_generation_type = 'generate_exam' and v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then raise exception 'Exames de imagem usam a geração visual completa.'; end if;
  if p_source_image_generation_id is not null and not exists (
    select 1 from public.exam_ai_generations source
    where source.id = p_source_image_generation_id and source.exam_id = p_exam_id
      and source.generation_type = 'generate_image' and source.status = 'completed' and source.draft_storage_path is not null
  ) then raise exception 'O rascunho de imagem selecionado não está disponível.'; end if;
  if p_source_image_id is not null and not exists (
    select 1 from public.clinical_exam_images image where image.id = p_source_image_id and image.exam_id = p_exam_id and image.removed_at is null
  ) then raise exception 'A imagem selecionada não está disponível.'; end if;

  select * into v_generation from public.exam_ai_generations
  where exam_id = p_exam_id and generation_type = p_generation_type and status = 'requested'
  order by created_at desc limit 1 for update;
  if v_generation.id is not null and v_generation.created_at >= now() - interval '2 minutes' then
    return jsonb_build_object('generation_id', v_generation.id, 'status', 'requested', 'suggestion', null, 'replayed', true);
  elsif v_generation.id is not null then
    update public.exam_ai_generations set status = 'failed', failed_at = now(), error_code = 'stale_request' where id = v_generation.id;
  end if;

  select count(*)::integer into v_recent_count from public.exam_ai_generations
  where requested_by = p_requested_by and created_at >= now() - interval '10 minutes';
  if v_recent_count >= 6 then raise exception 'Limite temporário de gerações atingido. Aguarde alguns minutos.'; end if;

  insert into public.exam_ai_generations (
    exam_id, generation_type, requested_by, model, reasoning_effort, prompt_version, source_exam_updated_at,
    source_image_generation_id, source_image_id, idempotency_key
  ) values (
    p_exam_id, p_generation_type, p_requested_by, 'gpt-5.6-luna', 'low', v_prompt_version, v_exam.updated_at,
    p_source_image_generation_id, p_source_image_id, p_idempotency_key
  ) returning * into v_generation;

  perform private.audit_exam_action(
    p_requested_by, 'clinical_exam.ai_requested', 'exam_ai_generations', v_generation.id::text, null,
    jsonb_build_object('exam_id', p_exam_id, 'generation_type', p_generation_type, 'model', v_generation.model,
      'prompt_version', v_generation.prompt_version, 'source_image_generation_id', p_source_image_generation_id, 'source_image_id', p_source_image_id)
  );
  return jsonb_build_object('generation_id', v_generation.id, 'status', v_generation.status, 'suggestion', null, 'replayed', false);
end;
$function$;

CREATE OR REPLACE FUNCTION public.begin_clinical_exam_ai_image(p_exam_id bigint, p_requested_by uuid, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_exam public.clinical_exams; v_generation public.exam_ai_generations; v_recent integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_exam_id::text || ':generate_image', 0));
  select * into v_generation from public.exam_ai_generations where idempotency_key = p_idempotency_key for update;
  if v_generation.id is not null then
    if v_generation.exam_id <> p_exam_id or v_generation.requested_by <> p_requested_by or v_generation.generation_type <> 'generate_image' then raise exception 'Chave de idempotência inválida.'; end if;
    return jsonb_build_object('generation_id', v_generation.id, 'status', v_generation.status, 'replayed', true);
  end if;
  select * into v_exam from public.clinical_exams where id = p_exam_id for update;
  if v_exam.id is null or v_exam.status <> 'in_progress' or v_exam.result_data->>'schema' <> 'hpsm.image_result.v1' then raise exception 'O exame não aceita geração de imagem.'; end if;
  if v_exam.responsible_professional_id is distinct from p_requested_by or not private.has_permission(p_requested_by, 'exams.perform') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_generation from public.exam_ai_generations where exam_id = p_exam_id and generation_type = 'generate_image' and status = 'requested' order by created_at desc limit 1 for update;
  if v_generation.id is not null and v_generation.created_at >= now() - interval '2 minutes' then return jsonb_build_object('generation_id', v_generation.id, 'status', 'requested', 'replayed', true); end if;
  if v_generation.id is not null then update public.exam_ai_generations set status = 'failed', failed_at = now(), error_code = 'stale_request' where id = v_generation.id; end if;
  select count(*) into v_recent from public.exam_ai_generations where requested_by = p_requested_by and generation_type = 'generate_image' and created_at >= now() - interval '10 minutes';
  if v_recent >= 4 then raise exception 'Limite temporário de imagens atingido. Aguarde alguns minutos.'; end if;
  insert into public.exam_ai_generations(exam_id, generation_type, requested_by, model, reasoning_effort, prompt_version, source_exam_updated_at, idempotency_key, image_quality, image_size, image_count)
  values(p_exam_id, 'generate_image', p_requested_by, 'gpt-image-2', 'low', 'exam-image-rp-v2', v_exam.updated_at, p_idempotency_key, 'low', '1024x1024', 1) returning * into v_generation;
  perform private.audit_exam_action(p_requested_by, 'clinical_exam.ai_image_requested', 'exam_ai_generations', v_generation.id::text, null,
    jsonb_build_object('exam_id', p_exam_id, 'model', 'gpt-image-2', 'quality', 'low', 'size', '1024x1024', 'image_count', 1, 'prompt_version', 'exam-image-rp-v2'));
  return jsonb_build_object('generation_id', v_generation.id, 'status', 'requested', 'replayed', false);
end;
$function$;

CREATE OR REPLACE FUNCTION public.begin_professional_identity_generation(p_target_user_id uuid, p_actor_id uuid, p_operation text, p_idempotency_key uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_identity public.professional_identities;
  v_is_director boolean := private.hpsm_identity_is_director_general(p_actor_id);
  v_profile public.profiles;
  v_operation text := case when p_operation = 'initial' then 'initial' else p_operation end;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if p_target_user_id is null or p_actor_id is null or p_idempotency_key is null
     or v_operation not in ('initial', 'regenerate', 'reprocess') then
    raise exception 'Solicitacao de identidade invalida.' using errcode = '22023';
  end if;
  select * into v_profile from public.profiles where user_id = p_target_user_id;
  if not found then raise exception 'Profissional nao localizado.' using errcode = 'P0002'; end if;
  if v_profile.status <> 'active' and not v_is_director then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;
  if v_profile.must_change_password then
    raise exception 'Conclua a troca obrigatoria de senha antes da identidade.' using errcode = '42501';
  end if;
  if p_actor_id <> p_target_user_id and not v_is_director then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;
  if v_operation in ('regenerate', 'reprocess') and not v_is_director then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;
  if v_operation in ('regenerate', 'reprocess') and (v_reason is null or char_length(v_reason) not between 5 and 500) then
    raise exception 'Informe o motivo da regeneracao.' using errcode = '22023';
  end if;

  select * into v_identity
  from public.professional_identities
  where user_id = p_target_user_id
  for update;
  if not found then raise exception 'Identidade profissional nao localizada.' using errcode = 'P0002'; end if;

  if v_operation = 'initial' and v_identity.status = 'active' then
    return jsonb_build_object('generation_id', null, 'replayed', true, 'status', 'active');
  end if;
  if v_identity.status = 'generating'
     and v_identity.generation_started_at > now() - interval '5 minutes' then
    return jsonb_build_object('generation_id', v_identity.current_generation_id, 'replayed', true, 'status', 'generating');
  end if;
  if v_operation = 'regenerate' and (v_identity.signature_image_path is null or v_identity.rubric_image_path is null) then
    raise exception 'Use o reprocessamento para uma identidade ainda incompleta.' using errcode = '22023';
  end if;

  update public.professional_identities
  set status = 'generating',
      current_generation_id = p_idempotency_key,
      generation_operation = v_operation,
      generation_started_at = now(),
      signature_regeneration_reason = case when v_operation = 'initial' then signature_regeneration_reason else v_reason end,
      last_failure_code = null,
      updated_at = now()
  where user_id = p_target_user_id;

  return jsonb_build_object(
    'generation_id', p_idempotency_key,
    'replayed', false,
    'status', 'generating',
    'generation_version', v_identity.generation_version
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_attendance(p_attendance_id bigint)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.cancel_attendance(p_attendance_id);
$function$;

CREATE OR REPLACE FUNCTION public.cancel_clinical_cast(p_cast_id bigint, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid;
  v_old public.clinical_casts;
  v_new public.clinical_casts;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null or not private.has_permission(v_actor, 'casts.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if char_length(v_reason) not between 2 and 500 then raise exception 'Informe o motivo do cancelamento.'; end if;
  select * into v_old from public.clinical_casts where id = p_cast_id for update;
  if v_old.id is null then raise exception 'Registro de gesso não localizado.'; end if;
  if v_old.status <> 'in_use' then raise exception 'Somente um gesso em uso pode ser cancelado.'; end if;

  update public.clinical_casts
  set status = 'cancelled', cancelled_at = now(), cancelled_by = v_actor, cancellation_reason = v_reason
  where id = p_cast_id
  returning * into v_new;

  perform private.audit_cast_action(
    v_actor, 'CAST_CANCELLED', v_new.id,
    jsonb_build_object('status', v_old.status),
    jsonb_build_object(
      'status', v_new.status,
      'cancelled_at', v_new.cancelled_at,
      'cancelled_by', v_new.cancelled_by,
      'reason', v_new.cancellation_reason
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_hr_leave_request(p_request_id bigint, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row public.rh_absence_requests;
begin
  update public.rh_absence_requests
  set status = 'cancelled',
      cancelled_by = p_actor_id,
      cancelled_at = now(),
      updated_at = now()
  where id = p_request_id
    and employee_id = p_actor_id
    and status = 'pending'
  returning * into v_row;

  if not found then
    raise exception using errcode = 'P0002', message = 'A solicitação não está disponível para cancelamento.';
  end if;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_partnership_pending(p_pending_id bigint, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_pending public.partnership_pending_beneficiaries%rowtype;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if char_length(v_reason) not between 2 and 500 then raise exception 'Informe o motivo do cancelamento.' using errcode = '22023'; end if;
  select * into v_pending from public.partnership_pending_beneficiaries where id = p_pending_id for update;
  if not found or v_pending.status not in ('pending_registration', 'name_review') then
    raise exception 'Pré-beneficiário pendente não localizado.' using errcode = '22023';
  end if;
  update public.partnership_pending_beneficiaries set status = 'canceled', canceled_at = now(),
    canceled_by_type = 'professional', canceled_by_user_id = v_actor, cancellation_reason = v_reason
  where id = p_pending_id;
  perform private.partnership_audit('PARTNERSHIP_PENDING_CANCELED', 'partnership_pending_beneficiaries', p_pending_id::text,
    'professional', v_actor, null, null,
    jsonb_build_object('partnership_id', v_pending.partnership_id, 'passport', v_pending.passport, 'reason', v_reason));
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_cast_attendance_options(p_patient_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid;
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null
     or not private.has_permission(v_actor, 'casts.create')
     or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', option.id,
      'created_at', option.created_at,
      'total', option.total,
      'has_cast_item', option.has_cast_item,
      'summary', coalesce((
        select string_agg(item.service_name || case when item.quantity > 1 then ' ×' || item.quantity::text else '' end, ', ' order by item.id)
        from public.attendance_items item where item.attendance_id = option.id
      ), 'Atendimento sem itens')
    ) order by option.has_cast_item desc, option.created_at desc)
    from (
      select
        attendance.id,
        attendance.created_at,
        attendance.total,
        exists (
          select 1
          from public.attendance_items item
          join public.service_catalog catalog on catalog.id = item.service_id
          where item.attendance_id = attendance.id
            and catalog.code = 'gesso'
        ) as has_cast_item
      from public.attendances attendance
      where attendance.patient_id = p_patient_id and attendance.status = 'completed'
      order by has_cast_item desc, attendance.created_at desc
      limit 30
    ) option
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_cast_detail(p_cast_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid;
  v_result jsonb;
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null or not private.has_permission(v_actor, 'casts.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', cast_record.id,
    'patient_id', cast_record.patient_id,
    'patient_name', patient.name,
    'patient_passport', patient.passport,
    'attendance_id', cast_record.attendance_id,
    'attendance_created_at', attendance.created_at,
    'attendance_total', attendance.total,
    'attendance_summary', case when attendance.id is null then null else coalesce((
      select string_agg(item.service_name || case when item.quantity > 1 then ' ×' || item.quantity::text else '' end, ', ' order by item.id)
      from public.attendance_items item where item.attendance_id = attendance.id
    ), 'Atendimento sem itens') end,
    'body_region', cast_record.body_region,
    'laterality', cast_record.laterality,
    'status', cast_record.status,
    'applied_at', cast_record.applied_at,
    'applied_by', cast_record.applied_by,
    'applied_by_name', applied.display_name,
    'applied_by_position', applied_position.name,
    'expected_removal_at', cast_record.expected_removal_at,
    'application_notes', cast_record.application_notes,
    'removed_at', cast_record.removed_at,
    'removed_by', cast_record.removed_by,
    'removed_by_name', removed.display_name,
    'removed_by_position', removed_position.name,
    'removal_notes', cast_record.removal_notes,
    'cancelled_at', cast_record.cancelled_at,
    'cancelled_by', cast_record.cancelled_by,
    'cancelled_by_name', cancelled.display_name,
    'cancelled_by_position', cancelled_position.name,
    'cancellation_reason', cast_record.cancellation_reason,
    'created_at', cast_record.created_at,
    'updated_at', cast_record.updated_at
  ) into v_result
  from public.clinical_casts cast_record
  join public.patients patient on patient.id = cast_record.patient_id
  left join public.attendances attendance on attendance.id = cast_record.attendance_id
  join public.profiles applied on applied.user_id = cast_record.applied_by
  left join public.staff_positions applied_position on applied_position.id = applied.position_id
  left join public.profiles removed on removed.user_id = cast_record.removed_by
  left join public.staff_positions removed_position on removed_position.id = removed.position_id
  left join public.profiles cancelled on cancelled.user_id = cast_record.cancelled_by
  left join public.staff_positions cancelled_position on cancelled_position.id = cancelled.position_id
  where cast_record.id = p_cast_id;

  if v_result is null then raise exception 'Registro de gesso não localizado.'; end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_cast_overdue_page(p_limit integer DEFAULT 250)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_limit integer := least(greatest(coalesce(p_limit, 250), 1), 250);
begin
  if not private.has_permission(v_actor, 'casts.view')
     or not private.has_permission(v_actor, 'casts.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', due.id,
      'patient_id', due.patient_id,
      'patient_name', due.patient_name,
      'patient_passport', due.patient_passport,
      'body_region', due.body_region,
      'laterality', due.laterality,
      'status', due.status,
      'applied_at', due.applied_at,
      'expected_removal_at', due.expected_removal_at,
      'applied_by', due.applied_by,
      'applied_by_name', due.applied_by_name,
      'applied_by_position', due.applied_by_position
    ) order by due.expected_removal_at, due.id)
    from (
      select
        cast_record.id,
        cast_record.patient_id,
        patient.name as patient_name,
        patient.passport as patient_passport,
        cast_record.body_region,
        cast_record.laterality,
        cast_record.status,
        cast_record.applied_at,
        cast_record.expected_removal_at,
        cast_record.applied_by,
        applied.display_name as applied_by_name,
        applied_position.name as applied_by_position
      from public.clinical_casts cast_record
      join public.patients patient on patient.id = cast_record.patient_id
      join public.profiles applied on applied.user_id = cast_record.applied_by
      left join public.staff_positions applied_position on applied_position.id = applied.position_id
      where cast_record.status = 'in_use'
        and cast_record.expected_removal_at <= now()
      order by cast_record.expected_removal_at, cast_record.id
      limit v_limit
    ) due
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_cast_page(p_search text DEFAULT NULL::text, p_status text DEFAULT 'in_use'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid;
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null or not private.has_permission(v_actor, 'casts.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('in_use', 'removed', 'cancelled') then
    raise exception 'Status de gesso inválido.';
  end if;

  with filtered as (
    select
      cast_record.id,
      cast_record.patient_id,
      patient.name as patient_name,
      patient.passport as patient_passport,
      cast_record.attendance_id,
      cast_record.body_region,
      cast_record.laterality,
      cast_record.status,
      cast_record.applied_at,
      cast_record.expected_removal_at,
      cast_record.removed_at,
      cast_record.applied_by,
      applied.display_name as applied_by_name,
      applied_position.name as applied_by_position,
      cast_record.updated_at
    from public.clinical_casts cast_record
    join public.patients patient on patient.id = cast_record.patient_id
    join public.profiles applied on applied.user_id = cast_record.applied_by
    left join public.staff_positions applied_position on applied_position.id = applied.position_id
    where (p_status is null or cast_record.status = p_status)
      and (
        nullif(btrim(p_search), '') is null
        or patient.name ilike '%' || btrim(p_search) || '%'
        or patient.passport ilike btrim(p_search) || '%'
      )
  ), counted as (
    select count(*)::integer as total from filtered
  ), page_rows as (
    select *
    from filtered
    order by
      case when status = 'in_use' then 0 else 1 end,
      case when status = 'in_use' then expected_removal_at end asc,
      case when status <> 'in_use' then updated_at end desc,
      id desc
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(to_jsonb(page_rows) order by
      case when status = 'in_use' then 0 else 1 end,
      case when status = 'in_use' then expected_removal_at end asc,
      case when status <> 'in_use' then updated_at end desc,
      id desc
    ) from page_rows), '[]'::jsonb),
    'total', (select total from counted)
  ) into v_result;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_exam_ai_context(p_exam_id bigint, p_generation_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_category_code text;
  v_category_name text;
  v_type_code text;
  v_type_name text;
  v_report_config jsonb;
  v_lab_template jsonb;
  v_result_context jsonb := '{}'::jsonb;
begin
  if p_generation_type not in ('generate_lab_results', 'generate_report', 'generate_exam') then raise exception 'Operação de IA inválida.'; end if;
  select * into v_exam from public.clinical_exams exam where exam.id = p_exam_id;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'in_progress' then raise exception 'A IA só pode auxiliar exames em execução.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, p_exam_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;

  select category.code, category.name, exam_type.code, exam_type.name
  into v_category_code, v_category_name, v_type_code, v_type_name
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = v_exam.exam_type_id;

  if p_generation_type = 'generate_exam' and v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then
    raise exception 'Exames de imagem usam a geração visual completa.';
  end if;
  v_report_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
  if p_generation_type in ('generate_lab_results', 'generate_exam') and v_exam.result_data->>'schema' = 'hpsm.lab_result.v1' then
    v_lab_template := jsonb_build_object(
      'schema', v_exam.result_data#>>'{template_snapshot,schema}',
      'version', v_exam.result_data->'template_version',
      'parameters', coalesce(v_exam.result_data#>'{template_snapshot,parameters}', '[]'::jsonb)
    );
  elsif p_generation_type = 'generate_lab_results' then
    raise exception 'A geração de resultados está disponível apenas para exames laboratoriais.';
  end if;

  if p_generation_type = 'generate_report' and v_exam.result_data->>'schema' = 'hpsm.lab_result.v1' then
    select jsonb_build_object(
      'kind', 'laboratory',
      'parameters', coalesce(jsonb_agg(jsonb_build_object(
        'key', parameter->>'key', 'label', parameter->>'label', 'value', parameter->>'value',
        'unit', parameter->>'unit', 'reference', parameter->>'reference', 'flag', parameter->'flag'
      ) order by (parameter->>'sort_order')::integer, parameter->>'label'), '[]'::jsonb),
      'notes', left(coalesce(v_exam.result_data->>'notes', ''), 4000)
    ) into v_result_context
    from jsonb_array_elements(v_exam.result_data->'parameters') parameter;
  elsif p_generation_type = 'generate_report' and v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then
    v_result_context := jsonb_build_object(
      'kind', 'imaging',
      'region', case when v_exam.result_data->>'region' = 'Outra região' then v_exam.result_data->>'other_region' else v_exam.result_data->>'region' end,
      'laterality', v_exam.result_data->>'laterality',
      'contrast', v_exam.result_data->>'contrast',
      'current_findings', left(coalesce(v_exam.findings, ''), 4000)
    );
  elsif p_generation_type = 'generate_report' then
    v_result_context := jsonb_build_object('kind', 'generic', 'observation', left(coalesce(v_exam.result_data->>'notes', ''), 4000));
  end if;

  return jsonb_build_object(
    'actor_id', v_actor,
    'exam_id', v_exam.id,
    'generation_type', p_generation_type,
    'patient_context', 'Paciente fictício do RP',
    'exam', jsonb_build_object('category_code', v_category_code, 'category_name', v_category_name, 'type_code', v_type_code, 'type_name', v_type_name),
    'case_context', jsonb_build_object('summary', private.clinical_exam_case_summary(v_exam.indication, v_exam.clinical_context)),
    'report_config', v_report_config,
    'lab_template', v_lab_template,
    'result_context', v_result_context
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_exam_ai_generations(p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid := private.hpsm_current_actor(); v_result jsonb;
begin
  if not private.has_permission(v_actor, 'exams.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if not exists (select 1 from public.clinical_exams exam where exam.id = p_exam_id) then raise exception 'Exame não localizado.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, p_exam_id) then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', generation.id, 'generation_type', generation.generation_type, 'status', generation.status,
    'model', generation.model, 'reasoning_effort', generation.reasoning_effort, 'prompt_version', generation.prompt_version,
    'suggestion_payload', generation.suggestion_payload, 'source_image_generation_id', generation.source_image_generation_id,
    'source_image_id', generation.source_image_id, 'created_at', generation.created_at,
    'completed_at', generation.completed_at, 'applied_at', generation.applied_at
  ) order by generation.generation_type, generation.state_rank), '[]'::jsonb) into v_result
  from (
    select distinct on (item.generation_type, case when item.status = 'applied' then 1 else 0 end)
      item.*, case when item.status = 'applied' then 1 else 0 end as state_rank
    from public.exam_ai_generations item
    where item.exam_id = p_exam_id and item.status in ('requested', 'completed', 'applied')
    order by item.generation_type, case when item.status = 'applied' then 1 else 0 end, item.created_at desc, item.id desc
  ) generation;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_exam_ai_image_context(p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_type_code text;
  v_type_name text;
begin
  select exam.* into v_exam from public.clinical_exams exam where exam.id = p_exam_id;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  select exam_type.code, exam_type.name into v_type_code, v_type_name from public.exam_types exam_type where exam_type.id = v_exam.exam_type_id;
  if v_exam.status <> 'in_progress' then raise exception 'A imagem por IA só pode ser gerada em exame em andamento.'; end if;
  if v_exam.responsible_professional_id is distinct from v_actor or not private.has_permission(v_actor, 'exams.perform') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_exam.result_data->>'schema' <> 'hpsm.image_result.v1' or v_type_code not in ('raio_x', 'tomografia', 'ressonancia_magnetica', 'ultrassom') then raise exception 'Este tipo de exame não aceita geração de imagem por IA.'; end if;
  if nullif(btrim(case when v_exam.result_data->>'region' = 'Outra região' then v_exam.result_data->>'other_region' else v_exam.result_data->>'region' end), '') is null
     or nullif(btrim(v_exam.indication), '') is null then
    raise exception 'Preencha e salve a região e a suspeita/contexto do caso antes de gerar.';
  end if;
  if coalesce((v_exam.result_data#>>'{template_snapshot,supports_laterality}')::boolean, false)
     and nullif(v_exam.result_data->>'laterality', '') is null then raise exception 'Selecione e salve a lateralidade antes de gerar.'; end if;

  return jsonb_build_object(
    'actor_id', v_actor,
    'exam_id', v_exam.id,
    'type_code', v_type_code,
    'type_name', v_type_name,
    'region', case when v_exam.result_data->>'region' = 'Outra região' then v_exam.result_data->>'other_region' else v_exam.result_data->>'region' end,
    'laterality', v_exam.result_data->>'laterality',
    'contrast', v_exam.result_data->>'contrast',
    'findings', left(coalesce(v_exam.findings, ''), 4000),
    'case_summary', private.clinical_exam_case_summary(v_exam.indication, v_exam.clinical_context)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_exam_ai_image_draft(p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid := private.hpsm_current_actor(); v_generation public.exam_ai_generations;
begin
  if not private.has_permission(v_actor,'exams.view') then raise exception 'Acesso não autorizado.' using errcode='42501'; end if;
  select generation.* into v_generation from public.exam_ai_generations generation join public.clinical_exams exam on exam.id=generation.exam_id
  where generation.exam_id=p_exam_id and generation.generation_type='generate_image' and generation.status in ('requested','completed')
    and exam.status='in_progress' and exam.responsible_professional_id=v_actor and private.has_permission(v_actor,'exams.perform')
  order by generation.created_at desc limit 1;
  if v_generation.id is null then return null; end if;
  return jsonb_build_object('id',v_generation.id,'status',v_generation.status,'model',v_generation.model,'prompt_version',v_generation.prompt_version,
    'quality',v_generation.image_quality,'size',v_generation.image_size,'image_count',v_generation.image_count,'storage_path',v_generation.draft_storage_path,
    'file_size',v_generation.draft_file_size,'created_at',v_generation.created_at,'completed_at',v_generation.completed_at);
end; $function$;

CREATE OR REPLACE FUNCTION public.clinical_exam_ai_visual_input(p_exam_id bigint, p_requested_by uuid, p_draft_generation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_exam public.clinical_exams;
  v_generation public.exam_ai_generations;
  v_image public.clinical_exam_images;
begin
  select * into v_exam from public.clinical_exams where id = p_exam_id;
  if v_exam.id is null or v_exam.status <> 'in_progress' then raise exception 'O exame não aceita geração de laudo.'; end if;
  if not private.can_access_clinical_exam_ai(p_requested_by, p_exam_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;

  if p_draft_generation_id is not null then
    select * into v_generation from public.exam_ai_generations
    where id = p_draft_generation_id and exam_id = p_exam_id and generation_type = 'generate_image'
      and status = 'completed' and draft_storage_path is not null;
    if v_generation.id is null then raise exception 'O rascunho de imagem selecionado não está disponível.'; end if;
  else
    select * into v_generation from public.exam_ai_generations
    where exam_id = p_exam_id and generation_type = 'generate_image' and status = 'completed' and draft_storage_path is not null
    order by completed_at desc nulls last, created_at desc, id desc limit 1;
  end if;

  if v_generation.id is not null then
    return jsonb_build_object(
      'source', 'draft', 'storage_path', v_generation.draft_storage_path, 'mime_type', v_generation.draft_mime_type,
      'source_image_generation_id', v_generation.id, 'source_image_id', null
    );
  end if;

  select * into v_image from public.clinical_exam_images
  where exam_id = p_exam_id and removed_at is null
  order by created_at desc, id desc limit 1;
  if v_image.id is null then return null; end if;
  return jsonb_build_object(
    'source', 'official', 'storage_path', v_image.storage_path, 'mime_type', v_image.mime_type,
    'source_image_generation_id', null, 'source_image_id', v_image.id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_exam_attendance_options(p_patient_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null
     or not private.has_permission(v_actor, 'exams.create')
     or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', attendance.id,
      'created_at', attendance.created_at,
      'total', attendance.total,
      'summary', coalesce((
        select string_agg(item.service_name || case when item.quantity > 1 then ' ×' || item.quantity::text else '' end, ', ' order by item.id)
        from public.attendance_items item
        where item.attendance_id = attendance.id
      ), 'Atendimento sem itens')
    ) order by attendance.created_at desc)
    from (
      select sale.id, sale.created_at, sale.total
      from public.attendances sale
      where sale.patient_id = p_patient_id
        and sale.status = 'completed'
        and exists (
          select 1
          from public.attendance_items item
          left join public.service_catalog catalog on catalog.id = item.service_id
          where item.attendance_id = sale.id
            and (
              upper(btrim(item.service_name)) in ('EXAMES / RAIO-X', 'RESSON. TOMO.')
              or upper(btrim(catalog.name)) in ('EXAMES / RAIO-X', 'RESSON. TOMO.')
            )
        )
      order by sale.created_at desc
      limit 30
    ) attendance
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_exam_detail(p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_result jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', exam.id,
    'patient', jsonb_build_object('id', patient.id, 'name', patient.name, 'passport', patient.passport),
    'exam_type', jsonb_build_object('id', exam_type.id, 'name', exam_type.name, 'category_id', category.id, 'category_name', category.name),
    'attendance_id', exam.attendance_id,
    'status', exam.status,
    'requested_by', jsonb_build_object('id', requester.user_id, 'name', requester.display_name, 'position', requester_position.name),
    'responsible_professional', jsonb_build_object('id', responsible.user_id, 'name', responsible.display_name, 'position', responsible_position.name),
    'reviewed_by', case when reviewer.user_id is null then null else jsonb_build_object('id', reviewer.user_id, 'name', reviewer.display_name, 'position', reviewer_position.name) end,
    'indication', exam.indication,
    'clinical_context', exam.clinical_context,
    'technique', exam.technique,
    'findings', exam.findings,
    'conclusion', exam.conclusion,
    'result_data', exam.result_data,
    'report_config', coalesce(exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(exam.exam_type_id)),
    'final_report_snapshot', exam.final_report_snapshot,
    'correction_reason', exam.correction_reason,
    'requested_at', exam.requested_at,
    'started_at', exam.started_at,
    'submitted_for_review_at', exam.submitted_for_review_at,
    'completed_at', exam.completed_at,
    'created_at', exam.created_at,
    'updated_at', exam.updated_at,
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', history.id,
        'from_status', history.from_status,
        'to_status', history.to_status,
        'note', history.note,
        'changed_at', history.changed_at,
        'changed_by', jsonb_build_object('id', changer.user_id, 'name', changer.display_name, 'position', changer_position.name)
      ) order by history.changed_at, history.id)
      from public.clinical_exam_status_history history
      join public.profiles changer on changer.user_id = history.changed_by
      left join public.staff_positions changer_position on changer_position.id = changer.position_id
      where history.exam_id = exam.id
    ), '[]'::jsonb),
    'report_versions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', version.id,
        'version_number', version.version_number,
        'decision', version.decision,
        'submitted_at', version.submitted_at,
        'submitted_by', jsonb_build_object('id', submitter.user_id, 'name', submitter.display_name, 'position', submitter_position.name),
        'reviewed_at', version.reviewed_at,
        'review_reason', version.review_reason,
        'reviewed_by', case when version_reviewer.user_id is null then null else jsonb_build_object('id', version_reviewer.user_id, 'name', version_reviewer.display_name, 'position', version_reviewer_position.name) end
      ) order by version.version_number)
      from public.clinical_exam_report_versions version
      join public.profiles submitter on submitter.user_id = version.submitted_by
      left join public.staff_positions submitter_position on submitter_position.id = submitter.position_id
      left join public.profiles version_reviewer on version_reviewer.user_id = version.reviewed_by
      left join public.staff_positions version_reviewer_position on version_reviewer_position.id = version_reviewer.position_id
      where version.exam_id = exam.id
    ), '[]'::jsonb)
  ) into v_result
  from public.clinical_exams exam
  join public.patients patient on patient.id = exam.patient_id
  join public.exam_types exam_type on exam_type.id = exam.exam_type_id
  join public.exam_categories category on category.id = exam_type.category_id
  join public.profiles requester on requester.user_id = exam.requested_by
  left join public.staff_positions requester_position on requester_position.id = requester.position_id
  join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
  left join public.staff_positions responsible_position on responsible_position.id = responsible.position_id
  left join public.profiles reviewer on reviewer.user_id = exam.reviewed_by
  left join public.staff_positions reviewer_position on reviewer_position.id = reviewer.position_id
  where exam.id = p_exam_id;

  if v_result is null then raise exception 'Exame não localizado.'; end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_exam_document_state(p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.clinical_exams exam
    where exam.id = p_exam_id
      and exam.status = 'completed'
      and exam.final_report_snapshot is not null
  ) then
    raise exception 'A imagem compartilhável está disponível somente para exames concluídos.';
  end if;

  return private.clinical_exam_document_state_json(p_exam_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_exam_image_gallery(p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid := auth.uid();
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.clinical_exams exam where exam.id = p_exam_id) then
    raise exception 'Exame não localizado.';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', image.id,
      'exam_id', image.exam_id,
      'storage_path', image.storage_path,
      'original_filename', image.original_filename,
      'mime_type', image.mime_type,
      'file_size', image.file_size,
      'sort_order', image.sort_order,
      'caption', image.caption,
      'source', image.source,
      'uploaded_by', image.uploaded_by,
      'created_at', image.created_at
    ) order by image.sort_order, image.created_at, image.id)
    from public.clinical_exam_images image
    where image.exam_id = p_exam_id and image.removed_at is null
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_exam_image_upload_context(p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_exam public.clinical_exams;
  v_count integer;
begin
  select * into v_exam from public.clinical_exams where id = p_exam_id;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_exam.responsible_professional_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_exam.status <> 'in_progress' then raise exception 'As imagens só podem ser alteradas enquanto o exame está em andamento.'; end if;
  if v_exam.result_data->>'schema' <> 'hpsm.image_result.v1' then raise exception 'Este exame não utiliza imagens clínicas.'; end if;
  select count(*) into v_count from public.clinical_exam_images image where image.exam_id = p_exam_id and image.removed_at is null;
  return jsonb_build_object(
    'active_image_count', v_count,
    'allows_multiple_images', (v_exam.result_data#>>'{template_snapshot,allows_multiple_images}')::boolean
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_exam_imaging_template_catalog()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid := auth.uid();
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.catalog.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', exam_type.id,
      'code', exam_type.code,
      'name', exam_type.name,
      'active', exam_type.active,
      'result_config', exam_type.result_config
    ) order by exam_type.sort_order, exam_type.name)
    from public.exam_types exam_type
    join public.exam_categories category on category.id = exam_type.category_id
    where category.code = 'imagem' and exam_type.result_config->>'kind' = 'imaging'
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_exam_page(p_search text DEFAULT NULL::text, p_passport text DEFAULT NULL::text, p_category_id bigint DEFAULT NULL::bigint, p_exam_type_id bigint DEFAULT NULL::bigint, p_status text DEFAULT NULL::text, p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('requested', 'in_progress', 'awaiting_review', 'completed') then
    raise exception 'Status inválido.';
  end if;

  with filtered as (
    select
      exam.id,
      exam.patient_id,
      patient.name as patient_name,
      patient.passport as patient_passport,
      exam.exam_type_id,
      exam_type.name as exam_type_name,
      category.id as category_id,
      category.name as category_name,
      exam.responsible_professional_id,
      responsible.display_name as responsible_name,
      position.name as responsible_position,
      exam.status,
      exam.requested_at
    from public.clinical_exams exam
    join public.patients patient on patient.id = exam.patient_id
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    join public.exam_categories category on category.id = exam_type.category_id
    join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
    left join public.staff_positions position on position.id = responsible.position_id
    where (nullif(btrim(p_search), '') is null or patient.name ilike '%' || btrim(p_search) || '%')
      and (nullif(btrim(p_passport), '') is null or patient.passport ilike btrim(p_passport) || '%')
      and (p_category_id is null or category.id = p_category_id)
      and (p_exam_type_id is null or exam_type.id = p_exam_type_id)
      and (p_status is null or exam.status = p_status)
      and (p_date_from is null or exam.requested_at >= p_date_from::timestamptz)
      and (p_date_to is null or exam.requested_at < (p_date_to + 1)::timestamptz)
  ), page_rows as (
    select * from filtered order by requested_at desc, id desc limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(to_jsonb(page_row) order by page_row.requested_at desc, page_row.id desc) from page_rows page_row), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_exam_reference_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not (
    private.has_permission(v_actor, 'exams.view')
    or private.has_permission(v_actor, 'exams.create')
    or private.has_permission(v_actor, 'exams.perform')
    or private.has_permission(v_actor, 'exams.review')
    or private.has_permission(v_actor, 'exams.catalog.manage')
  ) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', category.id,
        'code', category.code,
        'name', category.name,
        'active', category.active,
        'sort_order', category.sort_order
      ) order by category.sort_order, category.name)
      from public.exam_categories category
    ), '[]'::jsonb),
    'types', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', exam_type.id,
        'category_id', exam_type.category_id,
        'code', exam_type.code,
        'name', exam_type.name,
        'description', exam_type.description,
        'active', exam_type.active,
        'sort_order', exam_type.sort_order,
        'result_config', exam_type.result_config
      ) order by exam_type.category_id, exam_type.sort_order, exam_type.name)
      from public.exam_types exam_type
    ), '[]'::jsonb),
    'professionals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', profile.user_id,
        'name', profile.display_name,
        'position', position.name
      ))
      from public.profiles profile
      left join public.staff_positions position on position.id = profile.position_id
      where profile.user_id = v_actor
        and profile.status = 'active'
        and (private.has_permission(v_actor, 'exams.perform') or private.has_permission(v_actor, 'exams.review'))
    ), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.clinical_exam_template_catalog()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.catalog.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', exam_type.id,
      'code', exam_type.code,
      'name', exam_type.name,
      'active', exam_type.active,
      'result_config', exam_type.result_config
    ) order by exam_type.sort_order, exam_type.name)
    from public.exam_types exam_type
    join public.exam_categories category on category.id = exam_type.category_id
    where category.code = 'laboratorial'
      and exam_type.result_config->>'kind' = 'laboratory'
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.close_hr_week(p_employee_id uuid, p_week_start date, p_worked_minutes integer, p_calculation_details jsonb, p_closure_note text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles;
  v_week_end date := p_week_start + 6;
  v_cycle_month date := date_trunc('month', p_week_start + 6)::date;
  v_closure public.rh_week_closures;
  v_week public.rh_weekly_records;
  v_deduction integer := 0;
  v_required integer;
  v_deficit integer;
  v_credit integer := 0;
  v_justification_status text;
begin
  if not private.has_permission(p_actor_id, 'hr.weeks.close') then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode apurar semanas.';
  end if;
  if p_employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode apurar a própria semana.';
  end if;
  if p_week_start is null or extract(isodow from p_week_start) <> 1 then
    raise exception using errcode = '22023', message = 'A semana deve começar em uma segunda-feira.';
  end if;
  if v_week_end > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception using errcode = '22023', message = 'A semana ainda não terminou.';
  end if;
  if p_worked_minutes is null or p_worked_minutes not between 0 and 60000 then
    raise exception using errcode = '22023', message = 'Total semanal inválido.';
  end if;
  if p_closure_note is not null and char_length(p_closure_note) > 1000 then
    raise exception using errcode = '22023', message = 'A observação deve ter até 1000 caracteres.';
  end if;

  select * into v_profile
  from public.profiles
  where user_id = p_employee_id
  for update;
  if not found or v_profile.role_code = 'diretor_geral' or v_profile.status = 'inactive' then
    raise exception using errcode = '22023', message = 'Colaborador indisponível para apuração.';
  end if;

  insert into public.rh_week_closures (week_start, week_end, started_by)
  values (p_week_start, v_week_end, p_actor_id)
  on conflict (week_start) do update set updated_at = now()
  returning * into v_closure;

  if v_closure.status = 'closed' then
    raise exception using errcode = 'P0001', message = 'A semana já foi fechada. Reabra antes de corrigir.';
  end if;

  select least(600, coalesce(sum(adjustment.deducted_minutes), 0))::integer
  into v_deduction
  from public.rh_leave_week_adjustments adjustment
  join public.rh_absence_requests request on request.id = adjustment.leave_request_id
  where adjustment.employee_id = p_employee_id
    and adjustment.week_start = p_week_start
    and request.status = 'approved';

  v_required := greatest(0, 600 - v_deduction);
  v_deficit := greatest(0, v_required - p_worked_minutes);

  insert into public.rh_weekly_records (
    employee_id, week_start, week_end, cycle_month,
    base_required_minutes, leave_deduction_minutes, required_minutes,
    worked_minutes, deficit_minutes, justification_minutes, remaining_deficit_minutes,
    status, closure_status, closure_id, calculation_details, closure_note,
    closed_by, closed_at
  ) values (
    p_employee_id, p_week_start, v_week_end, v_cycle_month,
    600, v_deduction, v_required,
    p_worked_minutes, v_deficit, 0, v_deficit,
    case when v_deficit = 0 then 'met' else 'deficit' end,
    case when v_deficit = 0 then 'ready' else 'awaiting_justification' end,
    v_closure.id, coalesce(p_calculation_details, '{}'::jsonb), nullif(btrim(p_closure_note), ''),
    null, null
  )
  on conflict (employee_id, week_start) do update
  set closure_id = excluded.closure_id,
      week_end = excluded.week_end,
      cycle_month = excluded.cycle_month,
      base_required_minutes = excluded.base_required_minutes,
      leave_deduction_minutes = excluded.leave_deduction_minutes,
      required_minutes = excluded.required_minutes,
      worked_minutes = excluded.worked_minutes,
      deficit_minutes = excluded.deficit_minutes,
      justification_minutes = least(public.rh_weekly_records.justification_minutes, excluded.deficit_minutes),
      remaining_deficit_minutes = greatest(0, excluded.deficit_minutes - least(public.rh_weekly_records.justification_minutes, excluded.deficit_minutes)),
      status = case
        when greatest(0, excluded.deficit_minutes - least(public.rh_weekly_records.justification_minutes, excluded.deficit_minutes)) = 0
          then case when least(public.rh_weekly_records.justification_minutes, excluded.deficit_minutes) > 0 then 'justified' else 'met' end
        else 'deficit'
      end,
      closure_status = case
        when greatest(0, excluded.deficit_minutes - least(public.rh_weekly_records.justification_minutes, excluded.deficit_minutes)) = 0 then 'ready'
        else 'awaiting_justification'
      end,
      calculation_details = excluded.calculation_details,
      closure_note = excluded.closure_note,
      closed_by = null,
      closed_at = null,
      updated_at = now()
  returning * into v_week;

  select justification.status, coalesce(justification.credited_minutes, 0)
  into v_justification_status, v_credit
  from public.rh_hour_justifications justification
  where justification.weekly_record_id = v_week.id;

  if found then
    v_credit := least(v_credit, v_week.deficit_minutes);
    update public.rh_weekly_records
    set justification_minutes = v_credit,
        remaining_deficit_minutes = greatest(0, deficit_minutes - v_credit),
        status = case
          when greatest(0, deficit_minutes - v_credit) = 0 and v_credit > 0 then 'justified'
          when greatest(0, deficit_minutes - v_credit) = 0 then 'met'
          else 'deficit'
        end,
        closure_status = case
          when v_justification_status = 'pending' then 'justification_pending'
          else 'ready'
        end,
        updated_at = now()
    where id = v_week.id
    returning * into v_week;
  end if;

  return jsonb_build_object(
    'weekly_record_id', v_week.id,
    'status', v_week.status,
    'closure_status', v_week.closure_status,
    'base_required_minutes', v_week.base_required_minutes,
    'leave_deduction_minutes', v_week.leave_deduction_minutes,
    'required_minutes', v_week.required_minutes,
    'worked_minutes', v_week.worked_minutes,
    'remaining_deficit_minutes', v_week.remaining_deficit_minutes,
    'warning_id', null,
    'active_warnings', (
      select count(*) from public.rh_warnings warning
      where warning.employee_id = p_employee_id
        and warning.cycle_month = v_cycle_month
        and warning.status = 'active'
    ),
    'suspended', false
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_clinical_exam_ai_generation(p_generation_id uuid, p_openai_response_id text, p_input_tokens integer, p_output_tokens integer, p_total_tokens integer, p_suggestion_payload jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
begin
  select * into v_generation from public.exam_ai_generations where id = p_generation_id;
  if v_generation.id is null then raise exception 'Geração de IA não localizada.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_generation.exam_id::text || ':' || v_generation.generation_type, 0));
  select * into v_exam from public.clinical_exams where id = v_generation.exam_id for update;
  select * into v_generation from public.exam_ai_generations where id = p_generation_id for update;
  if v_generation.status <> 'requested' then raise exception 'A geração de IA já foi finalizada.'; end if;

  perform private.validate_exam_ai_suggestion(v_generation.exam_id, v_generation.generation_type, p_suggestion_payload);

  update public.exam_ai_generations
  set status = 'completed',
      openai_response_id = left(nullif(btrim(p_openai_response_id), ''), 200),
      input_tokens = greatest(coalesce(p_input_tokens, 0), 0),
      output_tokens = greatest(coalesce(p_output_tokens, 0), 0),
      total_tokens = greatest(coalesce(p_total_tokens, 0), 0),
      suggestion_payload = p_suggestion_payload,
      completed_at = now()
  where id = p_generation_id;

  perform private.audit_exam_action(
    v_generation.requested_by,
    'clinical_exam.ai_completed',
    'exam_ai_generations',
    p_generation_id::text,
    jsonb_build_object('status', 'requested'),
    jsonb_build_object('status', 'completed', 'exam_id', v_generation.exam_id, 'generation_type', v_generation.generation_type, 'model', v_generation.model, 'prompt_version', v_generation.prompt_version)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_clinical_exam_ai_image(p_generation_id uuid, p_openai_request_id text, p_storage_path text, p_file_size bigint, p_usage jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_generation public.exam_ai_generations; v_old_paths jsonb;
begin
  select * into v_generation from public.exam_ai_generations where id=p_generation_id for update;
  if v_generation.id is null or v_generation.generation_type <> 'generate_image' or v_generation.status <> 'requested' then raise exception 'Geração de imagem indisponível.'; end if;
  if p_storage_path !~ ('^clinical-exams/' || v_generation.exam_id::text || '/ai-drafts/[0-9a-f-]{36}\.png$') or p_file_size not between 1 and 10485760 then raise exception 'Rascunho de imagem inválido.'; end if;
  select coalesce(jsonb_agg(draft_storage_path),'[]'::jsonb) into v_old_paths from public.exam_ai_generations
    where exam_id=v_generation.exam_id and generation_type='generate_image' and status='completed' and draft_storage_path is not null;
  update public.exam_ai_generations set status='discarded',discarded_at=now() where exam_id=v_generation.exam_id and generation_type='generate_image' and status='completed';
  update public.exam_ai_generations set status='completed',openai_response_id=left(coalesce(nullif(btrim(p_openai_request_id),''),'request-unavailable'),200),
    input_tokens=greatest(coalesce((p_usage->>'input_tokens')::integer,0),0),output_tokens=greatest(coalesce((p_usage->>'output_tokens')::integer,0),0),
    total_tokens=greatest(coalesce((p_usage->>'total_tokens')::integer,0),0),suggestion_payload=jsonb_build_object('schema','hpsm.ai.image_draft.v1','storage_path',p_storage_path),
    draft_storage_path=p_storage_path,draft_mime_type='image/png',draft_file_size=p_file_size,completed_at=now() where id=p_generation_id;
  perform private.audit_exam_action(v_generation.requested_by,'clinical_exam.ai_image_completed','exam_ai_generations',p_generation_id::text,jsonb_build_object('status','requested'),jsonb_build_object('status','completed','exam_id',v_generation.exam_id));
  return jsonb_build_object('old_paths',v_old_paths);
end; $function$;

CREATE OR REPLACE FUNCTION public.complete_professional_identity_generation(p_target_user_id uuid, p_actor_id uuid, p_generation_id uuid, p_signature_path text, p_signature_file_size integer, p_rubric_path text, p_rubric_file_size integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_identity public.professional_identities;
  v_actor_passport text;
  v_initial boolean;
  v_now timestamptz := now();
begin
  select * into v_identity from public.professional_identities
  where user_id = p_target_user_id for update;
  if not found or v_identity.status <> 'generating' or v_identity.current_generation_id is distinct from p_generation_id then
    raise exception 'Geracao de identidade nao esta mais ativa.' using errcode = '40001';
  end if;
  if p_signature_path <> format('professionals/%s/%s/signature.png', p_target_user_id, p_generation_id)
     or p_rubric_path <> format('professionals/%s/%s/rubric.png', p_target_user_id, p_generation_id)
     or p_signature_file_size not between 32 and 5242880
     or p_rubric_file_size not between 32 and 5242880 then
    raise exception 'Arquivos de identidade invalidos.' using errcode = '22023';
  end if;

  v_initial := v_identity.generation_version = 0;
  select passport into v_actor_passport from public.profiles where user_id = p_actor_id;

  update public.professional_identities
  set signature_image_path = p_signature_path,
      rubric_image_path = p_rubric_path,
      signature_file_size = p_signature_file_size,
      rubric_file_size = p_rubric_file_size,
      signature_generated_at = coalesce(signature_generated_at, v_now),
      signature_generated_by = coalesce(signature_generated_by, p_actor_id),
      signature_regenerated_at = case when v_initial then signature_regenerated_at else v_now end,
      signature_regenerated_by = case when v_initial then signature_regenerated_by else p_actor_id end,
      signature_regeneration_reason = case when v_initial then signature_regeneration_reason else v_identity.signature_regeneration_reason end,
      identity_locked = true,
      status = 'active',
      generation_version = generation_version + 1,
      current_generation_id = null,
      generation_operation = null,
      generation_started_at = null,
      last_failure_code = null,
      updated_at = v_now
  where user_id = p_target_user_id;

  if v_initial then
    insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
    values
      (p_actor_id, v_actor_passport, 'IDENTITY_CRM_CREATED', 'professional_identities', p_target_user_id::text, null, jsonb_build_object('crm_code', v_identity.crm_code, 'registration_date', v_identity.registration_date)),
      (p_actor_id, v_actor_passport, 'IDENTITY_SIGNATURE_CREATED', 'professional_identities', p_target_user_id::text, null, jsonb_build_object('generation_version', 1)),
      (p_actor_id, v_actor_passport, 'IDENTITY_RUBRIC_CREATED', 'professional_identities', p_target_user_id::text, null, jsonb_build_object('generation_version', 1));
  else
    insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
    values
      (p_actor_id, v_actor_passport, 'IDENTITY_SIGNATURE_REGENERATED', 'professional_identities', p_target_user_id::text, jsonb_build_object('generation_version', v_identity.generation_version), jsonb_build_object('generation_version', v_identity.generation_version + 1, 'reason', v_identity.signature_regeneration_reason)),
      (p_actor_id, v_actor_passport, 'IDENTITY_RUBRIC_REGENERATED', 'professional_identities', p_target_user_id::text, jsonb_build_object('generation_version', v_identity.generation_version), jsonb_build_object('generation_version', v_identity.generation_version + 1, 'reason', v_identity.signature_regeneration_reason));
  end if;

  return jsonb_build_object('status', 'active', 'crm_code', v_identity.crm_code, 'generation_version', v_identity.generation_version + 1);
end;
$function$;

CREATE OR REPLACE FUNCTION public.correct_professional_identity_crm(p_target_user_id uuid, p_registration_date date, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_identity public.professional_identities;
  v_passport text;
  v_actor_passport text;
  v_new_crm text;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if not private.hpsm_identity_is_director_general(v_actor) then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;
  if p_registration_date is null or v_reason is null or char_length(v_reason) not between 5 and 500 then
    raise exception 'Informe a data e o motivo da correcao.' using errcode = '22023';
  end if;
  select * into v_identity from public.professional_identities where user_id = p_target_user_id for update;
  if not found then raise exception 'Identidade profissional nao localizada.' using errcode = 'P0002'; end if;
  select passport into v_passport from public.profiles where user_id = p_target_user_id;
  v_new_crm := private.hpsm_build_internal_crm(v_passport, p_registration_date);
  if v_new_crm = v_identity.crm_code and p_registration_date = v_identity.registration_date then
    return jsonb_build_object('crm_code', v_identity.crm_code, 'registration_date', v_identity.registration_date, 'changed', false);
  end if;
  update public.professional_identities
  set crm_code = v_new_crm, registration_date = p_registration_date, updated_at = now()
  where user_id = p_target_user_id;
  select passport into v_actor_passport from public.profiles where user_id = v_actor;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (v_actor, v_actor_passport, 'IDENTITY_CRM_CORRECTED', 'professional_identities', p_target_user_id::text,
    jsonb_build_object('crm_code', v_identity.crm_code, 'registration_date', v_identity.registration_date),
    jsonb_build_object('crm_code', v_new_crm, 'registration_date', p_registration_date, 'reason', v_reason));
  return jsonb_build_object('crm_code', v_new_crm, 'registration_date', p_registration_date, 'changed', true);
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_attendance(p_patient_id bigint, p_items jsonb, p_notes text DEFAULT NULL::text, p_benefit_code text DEFAULT NULL::text, p_partnership_id bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.create_attendance(p_patient_id, p_items, p_notes, p_benefit_code, p_partnership_id);
$function$;

CREATE OR REPLACE FUNCTION public.create_clinical_cast(p_patient_id bigint, p_attendance_id bigint, p_body_region text, p_laterality text, p_applied_at timestamp with time zone, p_expected_removal_at timestamp with time zone, p_application_notes text DEFAULT NULL::text, p_confirm_duplicate boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid;
  v_cast public.clinical_casts;
  v_notes text := nullif(btrim(coalesce(p_application_notes, '')), '');
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null
     or not private.has_permission(v_actor, 'casts.create')
     or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles profile where profile.user_id = v_actor and profile.status = 'active') then
    raise exception 'Profissional responsável não localizado.';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;
  if p_body_region not in ('hand', 'wrist', 'forearm', 'elbow', 'arm', 'foot', 'ankle', 'leg', 'knee', 'other') then
    raise exception 'Região inválida.';
  end if;
  if p_laterality not in ('right', 'left', 'bilateral', 'not_applicable') then
    raise exception 'Lateralidade inválida.';
  end if;
  if p_applied_at is null then raise exception 'Informe a data e hora da aplicação.'; end if;
  if p_expected_removal_at is null or p_expected_removal_at <= p_applied_at then
    raise exception 'A previsão de retirada deve ser posterior à aplicação.';
  end if;
  if v_notes is not null and char_length(v_notes) > 1000 then
    raise exception 'A observação deve ter no máximo 1000 caracteres.';
  end if;
  if p_attendance_id is not null and not exists (
    select 1 from public.attendances attendance
    where attendance.id = p_attendance_id
      and attendance.patient_id = p_patient_id
      and attendance.status = 'completed'
  ) then
    raise exception 'O atendimento informado não pertence ao paciente ou não está concluído.';
  end if;
  if not coalesce(p_confirm_duplicate, false) and exists (
    select 1 from public.clinical_casts active_cast
    where active_cast.patient_id = p_patient_id
      and active_cast.body_region = p_body_region
      and active_cast.laterality = p_laterality
      and active_cast.status = 'in_use'
  ) then
    raise exception 'O paciente já possui um gesso em uso na mesma região e lateralidade.'
      using errcode = '23505', detail = 'HPSM_ACTIVE_CAST_DUPLICATE';
  end if;

  insert into public.clinical_casts (
    patient_id, attendance_id, body_region, laterality, status,
    applied_at, applied_by, expected_removal_at, application_notes, created_by
  ) values (
    p_patient_id, p_attendance_id, p_body_region, p_laterality, 'in_use',
    p_applied_at, v_actor, p_expected_removal_at, v_notes, v_actor
  ) returning * into v_cast;

  perform private.audit_cast_action(
    v_actor, 'CAST_APPLIED', v_cast.id, null,
    jsonb_build_object(
      'patient_id', v_cast.patient_id,
      'attendance_id', v_cast.attendance_id,
      'body_region', v_cast.body_region,
      'laterality', v_cast.laterality,
      'applied_at', v_cast.applied_at,
      'expected_removal_at', v_cast.expected_removal_at,
      'status', v_cast.status
    )
  );
  return v_cast.id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_clinical_exam(p_patient_id bigint, p_exam_type_id bigint, p_responsible_professional_id uuid, p_indication text, p_clinical_context text DEFAULT NULL::text, p_attendance_id bigint DEFAULT NULL::bigint, p_initial_result_data jsonb DEFAULT NULL::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_responsible uuid := auth.uid();
  v_exam public.clinical_exams;
  v_base_result jsonb;
  v_candidate jsonb;
  v_result_data jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.create') or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_indication, '')), '') is null then
    raise exception 'Informe a indicação clínica.';
  end if;
  if char_length(btrim(p_indication)) > 4000 then
    raise exception 'A indicação clínica deve ter no máximo 4000 caracteres.';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;
  if not exists (
    select 1
    from public.exam_types exam_type
    join public.exam_categories category on category.id = exam_type.category_id
    where exam_type.id = p_exam_type_id and exam_type.active and category.active
  ) then
    raise exception 'Tipo de exame indisponível.';
  end if;
  if not exists (
    select 1
    from public.profiles profile
    where profile.user_id = v_responsible and profile.status = 'active'
  ) or not (
    private.has_permission(v_responsible, 'exams.perform')
    or private.has_permission(v_responsible, 'exams.review')
  ) then
    raise exception 'Seu perfil não está habilitado como profissional responsável.';
  end if;
  if p_attendance_id is not null and not exists (
    select 1
    from public.attendances sale
    where sale.id = p_attendance_id
      and sale.patient_id = p_patient_id
      and sale.status = 'completed'
      and exists (
        select 1
        from public.attendance_items item
        left join public.service_catalog catalog on catalog.id = item.service_id
        where item.attendance_id = sale.id
          and (
            upper(btrim(item.service_name)) in ('EXAMES / RAIO-X', 'RESSON. TOMO.')
            or upper(btrim(catalog.name)) in ('EXAMES / RAIO-X', 'RESSON. TOMO.')
          )
      )
  ) then
    raise exception 'O atendimento relacionado deve ser uma venda concluída deste paciente com EXAMES / RAIO-X ou RESSON. TOMO.';
  end if;

  -- O parâmetro legado permanece na assinatura durante a transição, mas a
  -- responsabilidade é sempre definida pela sessão autenticada.
  v_base_result := private.build_clinical_exam_result(p_exam_type_id);
  if v_base_result->>'schema' = 'hpsm.image_result.v1' then
    if p_initial_result_data is null or jsonb_typeof(p_initial_result_data) <> 'object' then
      raise exception 'Preencha as informações básicas do exame de imagem na solicitação.';
    end if;
    v_candidate := v_base_result || jsonb_build_object(
      'region', coalesce(p_initial_result_data->>'region', ''),
      'other_region', coalesce(p_initial_result_data->>'other_region', ''),
      'laterality', coalesce(p_initial_result_data->>'laterality', ''),
      'contrast', coalesce(p_initial_result_data->>'contrast', ''),
      'notes', ''
    );
    v_result_data := private.normalize_image_result(v_base_result, v_candidate);
    if coalesce((v_result_data#>>'{template_snapshot,region,required}')::boolean, false)
       and btrim(v_result_data->>'region') = '' then
      raise exception 'Informe a região examinada na solicitação.';
    end if;
    if coalesce((v_result_data#>>'{template_snapshot,supports_laterality}')::boolean, false)
       and btrim(v_result_data->>'laterality') = '' then
      raise exception 'Informe a lateralidade na solicitação.';
    end if;
    if coalesce((v_result_data#>>'{template_snapshot,supports_contrast}')::boolean, false)
       and btrim(v_result_data->>'contrast') = '' then
      raise exception 'Informe o uso de contraste na solicitação.';
    end if;
  else
    v_result_data := v_base_result;
  end if;

  v_result_data := private.attach_clinical_exam_report_context(p_exam_type_id, v_result_data);
  insert into public.clinical_exams (
    patient_id, exam_type_id, attendance_id, requested_by, responsible_professional_id,
    indication, clinical_context, result_data
  ) values (
    p_patient_id, p_exam_type_id, p_attendance_id, v_actor, v_responsible,
    btrim(p_indication),
    case when v_base_result->>'schema' = 'hpsm.image_result.v1' then null else nullif(btrim(p_clinical_context), '') end,
    v_result_data
  ) returning * into v_exam;

  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (v_exam.id, null, 'requested', v_actor, 'Exame solicitado.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.created', 'clinical_exams', v_exam.id::text, null, to_jsonb(v_exam));
  return v_exam.id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_clinical_exam_document_share(p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_document public.clinical_exam_documents;
  v_share public.clinical_exam_document_shares;
begin
  if not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select exam.* into v_exam
  from public.clinical_exams exam
  where exam.id = p_exam_id
  for update;

  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'completed' or v_exam.final_report_snapshot is null then
    raise exception 'O link está disponível somente para exames concluídos.';
  end if;

  select document.* into v_document
  from public.clinical_exam_documents document
  where document.exam_id = p_exam_id
    and document.render_version = 'exam-document-png-v4'
  limit 1;
  if v_document.id is null then raise exception 'Gere a imagem compartilhável antes de criar o link.'; end if;

  select share.* into v_share
  from public.clinical_exam_document_shares share
  where share.exam_id = p_exam_id and share.revoked_at is null
  limit 1;

  if v_share.id is null then
    insert into public.clinical_exam_document_shares (exam_id, document_id, created_by)
    values (p_exam_id, v_document.id, v_actor)
    returning * into v_share;

    perform private.audit_exam_action(
      v_actor,
      'clinical_exam.document_link_created',
      'clinical_exam_document_shares',
      v_share.id::text,
      null,
      jsonb_build_object('exam_id', p_exam_id, 'document_id', v_document.id)
    );
  end if;

  return private.clinical_exam_document_state_json(p_exam_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_course(p_name text, p_description text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row public.courses;
begin
  if not private.has_permission(p_actor_id, 'courses.manage')
     or coalesce(private.current_position_level(p_actor_id), 0) < 11 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para criar cursos.';
  end if;
  insert into public.courses (name, description, created_by, updated_by)
  values (btrim(p_name), btrim(coalesce(p_description, '')), p_actor_id, p_actor_id)
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_hr_leave_request(p_start_date date, p_end_date date, p_reason text, p_observation text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row public.rh_absence_requests;
begin
  if not exists (
    select 1 from public.profiles
    where user_id = p_actor_id
      and status = 'active'
      and role_code <> 'diretor_geral'
  ) then
    raise exception using errcode = '42501', message = 'Colaborador sem acesso ao controle de afastamentos.';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date
     or p_end_date > p_start_date + 89 then
    raise exception using errcode = '22023', message = 'Informe um período válido de até 90 dias.';
  end if;
  if p_start_date <= (now() at time zone 'America/Sao_Paulo')::date then
    raise exception using errcode = '22023', message = 'O afastamento deve ser solicitado antes do início da ausência.';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe o motivo entre 10 e 2000 caracteres.';
  end if;
  if p_observation is not null and nullif(btrim(p_observation), '') is not null
     and char_length(btrim(p_observation)) not between 2 and 2000 then
    raise exception using errcode = '22023', message = 'A observação deve ter entre 2 e 2000 caracteres.';
  end if;

  insert into public.rh_absence_requests (
    employee_id, start_date, end_date, reason, observation
  ) values (
    p_actor_id, p_start_date, p_end_date, btrim(p_reason), nullif(btrim(p_observation), '')
  ) returning * into v_row;

  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_partnership(p_name text, p_notes text DEFAULT NULL::text, p_responsible_patient_id bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_name text := btrim(coalesce(p_name, ''));
  v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
  v_id bigint;
begin
  if char_length(v_name) not between 2 and 120 then raise exception 'Informe o nome da parceria.' using errcode = '22023'; end if;
  if v_notes is not null and char_length(v_notes) > 2000 then raise exception 'A observação pode ter até 2.000 caracteres.' using errcode = '22023'; end if;
  if p_responsible_patient_id is not null and not private.partnership_patient_can_use_portal(p_responsible_patient_id) then
    raise exception 'O responsável precisa ser um paciente cadastrado com data de nascimento válida para acessar o Portal.' using errcode = '22023';
  end if;

  insert into public.partnerships (
    name, notes, responsible_patient_id, responsible_assigned_at, responsible_assigned_by,
    created_by, updated_by
  ) values (
    v_name, v_notes, p_responsible_patient_id,
    case when p_responsible_patient_id is null then null else now() end,
    case when p_responsible_patient_id is null then null else v_actor end,
    v_actor, v_actor
  ) returning id into v_id;

  insert into public.partnership_status_history (partnership_id, previous_status, status, changed_by)
  values (v_id, null, 'active', v_actor);
  if p_responsible_patient_id is not null then
    insert into public.partnership_responsible_history (partnership_id, previous_patient_id, responsible_patient_id, changed_by)
    values (v_id, null, p_responsible_patient_id, v_actor);
  end if;
  perform private.partnership_audit('PARTNERSHIP_CREATED', 'partnerships', v_id::text, 'professional', v_actor, null, null,
    jsonb_build_object('name', v_name, 'responsible_patient_id', p_responsible_patient_id, 'status', 'active'));
  return v_id;
exception when unique_violation then
  raise exception 'Já existe uma parceria com este nome.' using errcode = '23505';
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_staff_position(p_code text, p_name text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row public.staff_positions;
begin
  if not private.has_permission(p_actor_id, 'access.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para criar cargos.';
  end if;
  if p_code is null or p_code !~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'
     or char_length(btrim(coalesce(p_name, ''))) not between 2 and 80 then
    raise exception using errcode = '22023', message = 'Informe um nome de cargo válido.';
  end if;
  insert into public.staff_positions (code, name, created_by, updated_by)
  values (p_code, btrim(p_name), p_actor_id, p_actor_id)
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.decide_hr_disciplinary_review(p_review_id bigint, p_decision text, p_note text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_review public.rh_disciplinary_reviews;
  v_status text;
begin
  if not private.has_permission(p_actor_id, 'hr.discipline.review') then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode concluir análises disciplinares.';
  end if;
  if p_decision not in ('maintain_suspension', 'dismiss') then
    raise exception using errcode = '22023', message = 'Decisão disciplinar inválida.';
  end if;
  if char_length(btrim(coalesce(p_note, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe a fundamentação entre 10 e 2000 caracteres.';
  end if;

  select * into v_review
  from public.rh_disciplinary_reviews
  where id = p_review_id
  for update;

  if not found or v_review.status <> 'pending' then
    raise exception using errcode = 'P0002', message = 'Análise não encontrada ou já concluída.';
  end if;
  if v_review.employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode decidir a própria análise.';
  end if;

  perform 1 from public.profiles where user_id = v_review.employee_id for update;
  v_status := case when p_decision = 'dismiss' then 'dismissed' else 'suspension_maintained' end;

  update public.rh_disciplinary_reviews
  set status = v_status,
      decided_by = p_actor_id,
      decided_at = now(),
      decision_note = btrim(p_note),
      updated_at = now()
  where id = p_review_id
  returning * into v_review;

  update public.profiles
  set status = case when p_decision = 'dismiss' then 'inactive' else 'suspended' end,
      updated_by = p_actor_id,
      updated_at = now()
  where user_id = v_review.employee_id;

  return to_jsonb(v_review);
end;
$function$;

CREATE OR REPLACE FUNCTION public.decide_recruitment_application(p_application_id uuid, p_decision text, p_reason text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_decided_at timestamptz := now();
  v_reason text;
  v_decision_id bigint;
begin
  if not private.has_permission(p_actor_id, 'recruitment.manage') then
    raise exception using errcode = '42501', message = 'Apenas os cargos 11 a 14 podem decidir candidaturas.';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception using errcode = '22023', message = 'Decisão inválida.';
  end if;
  if p_decision = 'rejected' then
    v_reason := btrim(coalesce(p_reason, ''));
    if char_length(v_reason) not between 10 and 2000 then
      raise exception using errcode = '22023', message = 'Informe um motivo de recusa entre 10 e 2000 caracteres.';
    end if;
  else
    v_reason := null;
  end if;
  update public.recruitment_applications
  set status = p_decision, review_notes = v_reason,
      reviewed_by = p_actor_id, reviewed_at = v_decided_at
  where id = p_application_id and status in ('submitted', 'under_review', 'interview');
  if not found then
    raise exception using errcode = 'P0002', message = 'Candidatura não encontrada ou já decidida.';
  end if;
  insert into public.recruitment_decisions (
    application_id, decision, reason, decided_by, decided_at
  ) values (
    p_application_id, p_decision, v_reason, p_actor_id, v_decided_at
  ) returning id into v_decision_id;
  return jsonb_build_object(
    'application_id', p_application_id, 'decision_id', v_decision_id,
    'decision', p_decision, 'reason', v_reason,
    'decided_by', p_actor_id, 'decided_at', v_decided_at
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.decide_staff_promotion_review(p_review_id bigint, p_decision text, p_note text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_review public.staff_promotion_reviews;
  v_status jsonb;
  v_row public.staff_promotion_reviews;
begin
  if not private.has_permission(p_actor_id, 'progression.review')
     or coalesce(private.current_position_level(p_actor_id), 0) < 11 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para decidir promoções.';
  end if;
  if p_decision not in ('promoted', 'deferred')
     or (p_note is not null and char_length(btrim(p_note)) not between 2 and 2000) then
    raise exception using errcode = '22023', message = 'Decisão ou observação inválida.';
  end if;
  select * into v_review from public.staff_promotion_reviews where id = p_review_id for update;
  if not found or v_review.status not in ('pending', 'deferred')
     or (v_review.status = 'deferred' and p_decision = 'deferred') then
    raise exception using errcode = 'P0002', message = 'Análise de promoção não encontrada ou já decidida.';
  end if;
  if p_decision = 'promoted' then
    v_status := private.get_staff_progression_status(v_review.employee_id);
    if coalesce((v_status ->> 'eligible')::boolean, false) is not true
       or (v_status ->> 'position_id')::bigint <> v_review.from_position_id
       or (v_status ->> 'next_position_id')::bigint <> v_review.to_position_id then
      raise exception using errcode = '23514', message = 'O colaborador não atende mais aos requisitos da promoção.';
    end if;
    perform set_config('hpsm.position_change_authorized', 'true', true);
    update public.profiles
    set position_id = v_review.to_position_id, updated_by = p_actor_id, updated_at = now()
    where user_id = v_review.employee_id and position_id = v_review.from_position_id;
    if not found then
      raise exception using errcode = '40001', message = 'O cargo foi alterado durante a análise. Atualize a página.';
    end if;
    insert into public.staff_position_history (
      employee_id, from_position_id, to_position_id, event_type, decided_by, note
    ) values (
      v_review.employee_id, v_review.from_position_id, v_review.to_position_id,
      'promotion', p_actor_id, nullif(btrim(coalesce(p_note, '')), '')
    );
  end if;
  update public.staff_promotion_reviews
  set status = p_decision, decided_by = p_actor_id, decided_at = now(),
      decision_note = nullif(btrim(coalesce(p_note, '')), ''), updated_at = now()
  where id = p_review_id
  returning * into v_row;
  perform private.resolve_flow_notifications('staff_promotion_review', p_review_id::text, p_actor_id);
  insert into public.notifications (
    kind, recipient_id, priority, title, body, action_url, created_by
  ) values (
    'personal', v_review.employee_id,
    case when p_decision = 'promoted' then 'important' else 'normal' end,
    case when p_decision = 'promoted' then 'Promoção registrada' else 'Promoção mantida em análise' end,
    case when p_decision = 'promoted'
      then 'Seu novo cargo foi registrado. Consulte seu histórico no Meu RH.'
      else 'A análise foi concluída sem promoção neste momento. Sua elegibilidade continua visível.' end,
    '/meu-rh', p_actor_id
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.delete_clinical_exam(p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_storage_paths jsonb;
  v_image_ids text[];
  v_generation_ids text[];
  v_image_count integer;
  v_generation_count integer;
  v_report_version_count integer;
  v_history_count integer;
begin
  if v_actor is null then raise exception 'Sessão inválida.' using errcode = '42501'; end if;
  select * into v_exam from public.clinical_exams where id = p_exam_id for update;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status = 'completed' then raise exception 'Exames concluídos não podem ser excluídos.'; end if;
  if v_exam.responsible_professional_id is distinct from v_actor and not private.has_permission(v_actor, 'exams.delete') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(path order by path), '[]'::jsonb) into v_storage_paths
  from (
    select image.storage_path as path from public.clinical_exam_images image where image.exam_id = p_exam_id
    union
    select generation.draft_storage_path as path from public.exam_ai_generations generation
    where generation.exam_id = p_exam_id and generation.draft_storage_path is not null
  ) paths;
  select coalesce(array_agg(image.id::text), array[]::text[]), count(*)::integer
  into v_image_ids, v_image_count
  from public.clinical_exam_images image where image.exam_id = p_exam_id;
  select coalesce(array_agg(generation.id::text), array[]::text[]), count(*)::integer
  into v_generation_ids, v_generation_count
  from public.exam_ai_generations generation where generation.exam_id = p_exam_id;
  select count(*)::integer into v_report_version_count from public.clinical_exam_report_versions version where version.exam_id = p_exam_id;
  select count(*)::integer into v_history_count from public.clinical_exam_status_history history where history.exam_id = p_exam_id;

  delete from public.audit_logs audit
  where (audit.entity_name = 'clinical_exams' and audit.entity_id = p_exam_id::text)
     or (audit.entity_name = 'clinical_exam_images' and audit.entity_id = any(v_image_ids))
     or (audit.entity_name = 'exam_ai_generations' and audit.entity_id = any(v_generation_ids));
  delete from public.exam_ai_generations where exam_id = p_exam_id;
  delete from public.clinical_exam_images where exam_id = p_exam_id;
  delete from public.clinical_exam_report_versions where exam_id = p_exam_id;
  delete from public.clinical_exam_status_history where exam_id = p_exam_id;
  delete from public.clinical_exams where id = p_exam_id;

  perform private.audit_exam_action(
    v_actor,
    'DELETE',
    'clinical_exams',
    p_exam_id::text,
    jsonb_build_object(
      'status', v_exam.status,
      'exam_type_id', v_exam.exam_type_id,
      'patient_id', v_exam.patient_id,
      'responsible_professional_id', v_exam.responsible_professional_id
    ),
    jsonb_build_object(
      'deleted', true,
      'images', v_image_count,
      'ai_generations', v_generation_count,
      'report_versions', v_report_version_count,
      'status_events', v_history_count
    )
  );
  return jsonb_build_object('exam_id', p_exam_id, 'storage_paths', v_storage_paths);
end;
$function$;

CREATE OR REPLACE FUNCTION public.discard_clinical_exam_ai_generation(p_generation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
begin
  select * into v_generation from public.exam_ai_generations where id = p_generation_id;
  if v_generation.id is null then raise exception 'Sugestão de IA não localizada.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_generation.exam_id::text || ':' || v_generation.generation_type, 0));
  select * into v_exam from public.clinical_exams where id = v_generation.exam_id for update;
  select * into v_generation from public.exam_ai_generations where id = p_generation_id for update;

  if v_exam.status <> 'in_progress' then raise exception 'O exame não aceita mais alterações.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, v_exam.id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_generation.status <> 'completed' then raise exception 'A sugestão de IA não está disponível para descarte.'; end if;

  update public.exam_ai_generations set status = 'discarded', discarded_at = now() where id = p_generation_id;
  perform private.audit_exam_action(
    v_actor,
    'clinical_exam.ai_discarded',
    'exam_ai_generations',
    p_generation_id::text,
    jsonb_build_object('status', 'completed'),
    jsonb_build_object('status', 'discarded', 'exam_id', v_exam.id, 'generation_type', v_generation.generation_type)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.discard_clinical_exam_ai_image(p_generation_id uuid, p_actor uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_generation public.exam_ai_generations; v_exam public.clinical_exams;
begin
  select * into v_generation from public.exam_ai_generations where id=p_generation_id for update;
  if v_generation.id is null or v_generation.generation_type<>'generate_image' or v_generation.status<>'completed' then raise exception 'Rascunho de imagem indisponível.'; end if;
  select * into v_exam from public.clinical_exams where id=v_generation.exam_id for update;
  if v_exam.status<>'in_progress' or v_exam.responsible_professional_id is distinct from p_actor or not private.has_permission(p_actor,'exams.perform') then raise exception 'Acesso não autorizado.' using errcode='42501'; end if;
  update public.exam_ai_generations set status='discarded',discarded_at=now() where id=p_generation_id;
  perform private.audit_exam_action(p_actor,'clinical_exam.ai_image_discarded','exam_ai_generations',p_generation_id::text,jsonb_build_object('status','completed'),jsonb_build_object('status','discarded','exam_id',v_exam.id));
  return v_generation.draft_storage_path;
end; $function$;

CREATE OR REPLACE FUNCTION public.effective_permission_codes(p_user_id uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(array_agg(distinct effective.permission_code order by effective.permission_code), array[]::text[])
  from (
    select position_permission.permission_code
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id and position.active
    join public.staff_position_permissions position_permission on position_permission.position_id = position.id
    where profile.user_id = p_user_id
      and profile.status = 'active'
      and not profile.must_change_password
      and (
        position_permission.permission_code <> 'recruitment.manage'
        or position.level between 11 and 14
      )
    union all
    select permission_grant.permission_code
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id and position.active
    join public.user_permission_grants permission_grant on permission_grant.user_id = profile.user_id
    where profile.user_id = p_user_id
      and profile.status = 'active'
      and not profile.must_change_password
      and permission_grant.revoked_at is null
      and permission_grant.valid_from <= now()
      and (permission_grant.expires_at is null or permission_grant.expires_at > now())
      and (
        permission_grant.permission_code <> 'recruitment.manage'
        or position.level between 11 and 14
      )
  ) effective;
$function$;

CREATE OR REPLACE FUNCTION public.fail_clinical_exam_ai_generation(p_generation_id uuid, p_error_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_generation public.exam_ai_generations;
begin
  select * into v_generation from public.exam_ai_generations where id = p_generation_id;
  if v_generation.id is null then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_generation.exam_id::text || ':' || v_generation.generation_type, 0));
  select * into v_generation from public.exam_ai_generations where id = p_generation_id for update;
  if v_generation.status <> 'requested' then return; end if;

  update public.exam_ai_generations
  set status = 'failed', failed_at = now(), error_code = left(coalesce(nullif(btrim(p_error_code), ''), 'unknown_error'), 80)
  where id = p_generation_id;

  perform private.audit_exam_action(
    v_generation.requested_by,
    'clinical_exam.ai_failed',
    'exam_ai_generations',
    p_generation_id::text,
    jsonb_build_object('status', 'requested'),
    jsonb_build_object('status', 'failed', 'exam_id', v_generation.exam_id, 'generation_type', v_generation.generation_type, 'error_code', left(coalesce(p_error_code, 'unknown_error'), 80))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.fail_professional_identity_generation(p_target_user_id uuid, p_generation_id uuid, p_error_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.professional_identities
  set status = case when signature_image_path is not null and rubric_image_path is not null then 'active' else 'failed' end,
      identity_locked = true,
      current_generation_id = null,
      generation_operation = null,
      generation_started_at = null,
      last_failure_code = left(coalesce(nullif(btrim(p_error_code), ''), 'generation_failed'), 80),
      updated_at = now()
  where user_id = p_target_user_id
    and status = 'generating'
    and current_generation_id = p_generation_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.finalize_hr_week_closure(p_week_start date, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_closure public.rh_week_closures;
  v_count integer;
  v_deficits integer;
begin
  if not private.has_permission(p_actor_id, 'hr.weeks.close') then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode confirmar o fechamento.';
  end if;
  if p_week_start is null or extract(isodow from p_week_start) <> 1 then
    raise exception using errcode = '22023', message = 'Semana inválida.';
  end if;

  select * into v_closure
  from public.rh_week_closures
  where week_start = p_week_start
  for update;
  if not found or v_closure.status not in ('open', 'reopened') then
    raise exception using errcode = 'P0002', message = 'A semana não está disponível para fechamento.';
  end if;
  if v_closure.week_end > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception using errcode = '22023', message = 'A semana ainda não terminou.';
  end if;
  if exists (
    select 1
    from public.profiles profile
    where profile.role_code <> 'diretor_geral'
      and profile.status = 'active'
      and not exists (
        select 1 from public.rh_weekly_records record
        where record.closure_id = v_closure.id
          and record.employee_id = profile.user_id
      )
  ) then
    raise exception using errcode = 'P0001', message = 'Ainda existem colaboradores ativos sem apuração nesta semana.';
  end if;
  if exists (
    select 1 from public.rh_weekly_records
    where closure_id = v_closure.id and closure_status = 'justification_pending'
  ) then
    raise exception using errcode = 'P0001', message = 'Ainda existem justificativas enviadas aguardando análise.';
  end if;

  select count(*)::integer,
         count(*) filter (where remaining_deficit_minutes > 0)::integer
  into v_count, v_deficits
  from public.rh_weekly_records
  where closure_id = v_closure.id;
  if v_count = 0 then
    raise exception using errcode = 'P0001', message = 'Nenhum colaborador foi apurado nesta semana.';
  end if;

  update public.rh_weekly_records
  set closure_status = 'closed',
      closed_by = p_actor_id,
      closed_at = now(),
      updated_at = now()
  where closure_id = v_closure.id;

  update public.rh_week_closures
  set status = 'closed',
      closed_by = p_actor_id,
      closed_at = now(),
      updated_at = now()
  where id = v_closure.id
  returning * into v_closure;

  return jsonb_build_object(
    'closure', to_jsonb(v_closure),
    'records', v_count,
    'deficits', v_deficits
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_staff_progression_status(p_employee_id uuid, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_actor_id <> p_employee_id
     and not private.has_permission(p_actor_id, 'progression.review')
     and not private.has_permission(p_actor_id, 'hr.team.view') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para consultar esta progressão.';
  end if;
  return private.get_staff_progression_status(p_employee_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_staff_progression_statuses(p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_result jsonb;
begin
  if not private.has_permission(p_actor_id, 'progression.review')
     and not private.has_permission(p_actor_id, 'hr.team.view') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para consultar progressões.';
  end if;

  select coalesce(
    jsonb_object_agg(profile.user_id::text, private.get_staff_progression_status(profile.user_id)),
    '{}'::jsonb
  )
  into v_result
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  where profile.status = 'active'
    and position.level between 1 and 10;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.grant_temporary_permission(p_user_id uuid, p_permission_code text, p_valid_from timestamp with time zone, p_expires_at timestamp with time zone, p_reason text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.grant_user_permission(
    p_user_id, p_permission_code, 'temporary', p_valid_from,
    p_expires_at, p_reason, p_actor_id
  );
$function$;

CREATE OR REPLACE FUNCTION public.grant_user_permission(p_user_id uuid, p_permission_code text, p_grant_kind text, p_valid_from timestamp with time zone, p_expires_at timestamp with time zone, p_reason text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row public.user_permission_grants;
  v_start timestamptz := coalesce(p_valid_from, now());
begin
  if not private.has_permission(p_actor_id, 'access.grants.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para conceder acessos.';
  end if;
  if p_user_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Você não pode conceder uma permissão para si próprio.';
  end if;
  if not exists (select 1 from public.profiles where user_id = p_user_id and status <> 'inactive')
     or not exists (select 1 from public.system_permissions where code = p_permission_code)
     or p_permission_code in ('access.manage', 'access.grants.manage', 'succession.manage', 'settings.critical')
     or p_grant_kind not in ('individual', 'temporary')
     or (p_grant_kind = 'individual' and p_expires_at is not null)
     or (p_grant_kind = 'temporary' and (
       p_expires_at is null or p_expires_at <= v_start or p_expires_at > v_start + interval '180 days'
     ))
     or (p_reason is not null and char_length(btrim(p_reason)) not between 2 and 1000) then
    raise exception using errcode = '22023', message = 'Confira o profissional, a permissão e a validade.';
  end if;
  if exists (
    select 1 from public.user_permission_grants grant_row
    where grant_row.user_id = p_user_id
      and grant_row.permission_code = p_permission_code
      and grant_row.revoked_at is null
      and grant_row.valid_from <= coalesce(p_expires_at, 'infinity'::timestamptz)
      and coalesce(grant_row.expires_at, 'infinity'::timestamptz) > v_start
  ) then
    raise exception using errcode = '23505', message = 'Já existe uma concessão ativa ou sobreposta para esta permissão.';
  end if;
  insert into public.user_permission_grants (
    user_id, permission_code, grant_kind, valid_from, expires_at, reason, granted_by
  ) values (
    p_user_id, p_permission_code, p_grant_kind, v_start,
    case when p_grant_kind = 'temporary' then p_expires_at else null end,
    nullif(btrim(coalesce(p_reason, '')), ''), p_actor_id
  ) returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_attendance_history(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[] := public.effective_permission_codes(v_actor);
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 100);
  v_result jsonb;
begin
  if not (
    'attendances.create' = any(v_permissions)
    or 'attendances.manage' = any(v_permissions)
    or 'patients.view' = any(v_permissions)
  ) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', attendance.id,
      'patient_id', attendance.patient_id,
      'patient_name', attendance.patient_name,
      'patient_passport', attendance.patient_passport,
      'plan_code', attendance.plan_code,
      'plan_name', attendance.plan_name,
      'status', attendance.status,
      'subtotal', attendance.subtotal,
      'discount', attendance.discount,
      'total', attendance.total,
      'notes', attendance.notes,
      'performed_by', attendance.performed_by,
      'created_at', attendance.created_at,
      'professional_name', coalesce(profile.display_name, 'Profissional'),
      'professional_passport', coalesce(profile.passport, '—'),
      'professional_position', coalesce(position.name, 'Cargo não definido'),
      'attendance_items', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'id', item.id,
            'service_id', item.service_id,
            'service_name', item.service_name,
            'unit_price', item.unit_price,
            'quantity', item.quantity,
            'discount_percent', item.discount_percent,
            'discount_amount', item.discount_amount,
            'line_total', item.line_total
          ) order by item.id
        ), '[]'::jsonb)
        from public.attendance_items item
        where item.attendance_id = attendance.id
      )
    ) order by attendance.created_at desc, attendance.id desc
  ), '[]'::jsonb)
  into v_result
  from (
    select source.*
    from public.attendances source
    where source.performed_by = v_actor
       or 'attendances.manage' = any(v_permissions)
       or 'patients.view' = any(v_permissions)
    order by source.created_at desc, source.id desc
    limit v_limit
  ) attendance
  left join public.profiles profile on profile.user_id = attendance.performed_by
  left join public.staff_positions position on position.id = profile.position_id;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_attendance_history_page(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0, p_focus_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[] := public.effective_permission_codes(v_actor);
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_focus_created_at timestamptz;
  v_rows_before integer;
  v_result jsonb;
begin
  if not ('attendances.create' = any(v_permissions) or 'attendances.manage' = any(v_permissions) or 'patients.view' = any(v_permissions)) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_focus_id is not null then
    select target.created_at into v_focus_created_at from public.attendances target
    where target.id = p_focus_id and (target.performed_by = v_actor or 'attendances.manage' = any(v_permissions) or 'patients.view' = any(v_permissions));
    if found then
      select count(*)::integer into v_rows_before from public.attendances source
      where (source.performed_by = v_actor or 'attendances.manage' = any(v_permissions) or 'patients.view' = any(v_permissions))
        and (source.created_at, source.id) > (v_focus_created_at, p_focus_id);
      v_offset := (v_rows_before / v_limit) * v_limit;
    end if;
  end if;
  with visible as materialized (
    select source.* from public.attendances source
    where source.performed_by = v_actor or 'attendances.manage' = any(v_permissions) or 'patients.view' = any(v_permissions)
  ), page_rows as (
    select source.* from visible source order by source.created_at desc, source.id desc limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', attendance.id, 'patient_id', attendance.patient_id, 'patient_name', attendance.patient_name,
      'patient_passport', attendance.patient_passport, 'plan_code', attendance.plan_code,
      'plan_name', attendance.plan_name, 'partnership_id', attendance.partnership_id,
      'partnership_name', attendance.partnership_name, 'status', attendance.status,
      'subtotal', attendance.subtotal, 'discount', attendance.discount, 'total', attendance.total,
      'notes', attendance.notes, 'performed_by', attendance.performed_by, 'created_at', attendance.created_at,
      'professional_name', coalesce(profile.display_name, 'Profissional'),
      'professional_passport', coalesce(profile.passport, '—'),
      'professional_position', coalesce(position.name, 'Cargo não definido'),
      'attendance_items', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', item.id, 'service_id', item.service_id, 'service_name', item.service_name,
        'unit_price', item.unit_price, 'quantity', item.quantity, 'discount_percent', item.discount_percent,
        'discount_amount', item.discount_amount, 'line_total', item.line_total
      ) order by item.id), '[]'::jsonb) from public.attendance_items item where item.attendance_id = attendance.id)
    ) order by attendance.created_at desc, attendance.id desc) filter (where attendance.id is not null), '[]'::jsonb),
    'total', (select count(*) from visible), 'page', floor(v_offset::numeric / v_limit)::integer + 1, 'pageSize', v_limit
  ) into v_result
  from page_rows attendance
  left join public.profiles profile on profile.user_id = attendance.performed_by
  left join public.staff_positions position on position.id = profile.position_id;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_audit_page(p_limit integer DEFAULT 25, p_offset integer DEFAULT 0, p_action text DEFAULT NULL::text, p_entity text DEFAULT NULL::text, p_search text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_action text := nullif(btrim(coalesce(p_action, '')), '');
  v_entity text := nullif(lower(btrim(coalesce(p_entity, ''))), '');
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'audit.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if char_length(coalesce(v_action, '')) > 80
     or char_length(coalesce(v_entity, '')) > 80
     or char_length(coalesce(v_search, '')) > 100 then
    raise exception 'Filtro inválido.' using errcode = '22023';
  end if;

  with filtered as materialized (
    select
      audit.id,
      audit.actor_passport,
      audit.action,
      audit.entity_name,
      audit.entity_id,
      audit.created_at,
      position.name as actor_position
    from public.audit_logs audit
    left join public.profiles profile on profile.user_id = audit.actor_user_id
    left join public.staff_positions position on position.id = profile.position_id
    where (v_action is null or audit.action = v_action)
      and (v_entity is null or audit.entity_name = v_entity)
      and (
        v_search is null
        or coalesce(audit.actor_passport, '') ilike '%' || v_search || '%'
        or coalesce(profile.display_name, '') ilike '%' || v_search || '%'
        or coalesce(audit.entity_id, '') ilike '%' || v_search || '%'
        or audit.entity_name ilike '%' || v_search || '%'
      )
  ), page_rows as (
    select source.*
    from filtered source
    order by source.created_at desc, source.id desc
    limit v_limit
    offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', entry.id,
        'actor_passport', entry.actor_passport,
        'actor_position', entry.actor_position,
        'action', entry.action,
        'entity_name', entry.entity_name,
        'entity_id', entry.entity_id,
        'created_at', entry.created_at
      ) order by entry.created_at desc, entry.id desc
    ) filter (where entry.id is not null), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'page', floor(v_offset::numeric / v_limit)::integer + 1,
    'pageSize', v_limit
  )
  into v_result
  from page_rows entry;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_dashboard_bundle()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_summary jsonb := public.hpsm_dashboard_summary();
  v_preferences jsonb;
begin
  select jsonb_build_object(
    'configVersion', preference.config_version,
    'layouts', preference.layout_json,
    'hiddenWidgets', preference.hidden_widgets,
    'shortcuts', preference.shortcuts_json
  )
  into v_preferences
  from public.dashboard_preferences preference
  where preference.user_id = v_actor;

  return v_summary || jsonb_build_object('preferences', v_preferences);
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_dashboard_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[] := public.effective_permission_codes(v_actor);
  v_today date := timezone('America/Sao_Paulo', now())::date;
  v_week_start date;
  v_week_end date;
  v_cycle_month date;
  v_role_code text;
  v_current_position jsonb;
  v_weekly_inputs jsonb := null;
  v_production jsonb := '{}'::jsonb;
  v_career jsonb := '{}'::jsonb;
  v_attention_items jsonb := '[]'::jsonb;
  v_attention_total integer := 0;
  v_management_pending integer := 0;
  v_announcements jsonb := '[]'::jsonb;
  v_hospital jsonb := null;
  v_count integer := 0;
  v_recruitment_count integer := 0;
begin
  v_week_start := v_today - (extract(isodow from v_today)::integer - 1);
  v_week_end := v_week_start + 6;
  v_cycle_month := date_trunc('month', v_week_end)::date;

  select
    profile.role_code,
    jsonb_build_object(
      'id', position.id,
      'name', coalesce(position.name, 'Cargo não definido'),
      'level', position.level,
      'advancement_mode', position.advancement_mode
    )
  into v_role_code, v_current_position
  from public.profiles profile
  left join public.staff_positions position on position.id = profile.position_id
  where profile.user_id = v_actor
    and profile.status = 'active';

  if v_role_code is null then
    raise exception 'Perfil ativo não localizado.' using errcode = '42501';
  end if;

  -- Mesmos insumos mínimos usados pelo widget global e por Meu RH. O cálculo
  -- final permanece no helper canônico buildWeeklyProgress da aplicação.
  if v_role_code <> 'diretor_geral' then
    select jsonb_build_object(
      'snapshots', (
        select coalesce(jsonb_agg(to_jsonb(snapshot) order by snapshot.reading_date), '[]'::jsonb)
        from public.rh_hour_snapshots snapshot
        where snapshot.employee_id = v_actor
          and snapshot.reading_date >= date_trunc('month', v_week_start - 1)::date
          and snapshot.reading_date <= v_today
      ),
      'leaveAdjustments', (
        select coalesce(jsonb_agg(to_jsonb(adjustment) order by adjustment.week_start desc), '[]'::jsonb)
        from public.rh_leave_week_adjustments adjustment
        where adjustment.employee_id = v_actor
          and adjustment.week_start = v_week_start
      ),
      'weeklyRecords', (
        select coalesce(jsonb_agg(to_jsonb(record) order by record.week_start desc), '[]'::jsonb)
        from public.rh_weekly_records record
        where record.employee_id = v_actor
          and record.week_start = v_week_start
      ),
      'warnings', (
        select coalesce(jsonb_agg(to_jsonb(warning) order by warning.issued_at desc), '[]'::jsonb)
        from public.rh_warnings warning
        where warning.employee_id = v_actor
          and warning.cycle_month = v_cycle_month
      )
    ) into v_weekly_inputs;
  end if;

  -- Mesma definição financeira da Fase 8: somente atendimentos concluídos,
  -- total histórico do atendimento e quantidades preservadas nos itens.
  with week_attendances as materialized (
    select attendance.id, attendance.total
    from public.attendances attendance
    where attendance.performed_by = v_actor
      and attendance.status = 'completed'
      and attendance.created_at >= (v_week_start::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < ((v_week_end + 1)::timestamp at time zone 'America/Sao_Paulo')
  )
  select jsonb_build_object(
    'attendance_count', count(*)::integer,
    'item_count', coalesce((
      select sum(item.quantity)::integer
      from public.attendance_items item
      join week_attendances attendance on attendance.id = item.attendance_id
    ), 0),
    'total_amount', coalesce(sum(attendance.total), 0)
  )
  into v_production
  from week_attendances attendance;

  v_career := jsonb_build_object(
    'current_position', coalesce(v_current_position, 'null'::jsonb),
    'progression', coalesce(private.get_staff_progression_status(v_actor), '{}'::jsonb)
  );

  -- Pendências pessoais reais. Não criam estado paralelo e apenas apontam
  -- para Meu RH, onde a ação ou o acompanhamento continuam acontecendo.
  select count(*)::integer into v_count
  from public.rh_weekly_records record
  where record.employee_id = v_actor
    and record.week_start = v_week_start
    and record.closure_status in ('awaiting_justification', 'justification_pending');
  if v_count > 0 then
    v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
      'kind', 'personal_hours',
      'count', v_count,
      'href', '/meu-rh',
      'label', case
        when exists (
          select 1 from public.rh_weekly_records record
          where record.employee_id = v_actor
            and record.week_start = v_week_start
            and record.closure_status = 'awaiting_justification'
        ) then 'Justificativa de horas necessária'
        else 'Justificativa de horas em análise'
      end,
      'tone', 'important'
    ));
    v_attention_total := v_attention_total + v_count;
  end if;

  select count(*)::integer into v_count
  from public.rh_absence_requests absence
  where absence.employee_id = v_actor
    and absence.status = 'pending';
  if v_count > 0 then
    v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
      'kind', 'personal_absence',
      'count', v_count,
      'href', '/meu-rh',
      'label', 'Afastamento aguardando análise',
      'tone', 'normal'
    ));
    v_attention_total := v_attention_total + v_count;
  end if;

  -- As filas administrativas repetem exatamente a matriz da Central de
  -- Pendências. Cada tabela só é consultada quando a permissão efetiva existe.
  if 'recruitment.manage' = any(v_permissions) then
    select count(*)::integer into v_count
    from public.recruitment_applications application
    where application.status in ('submitted', 'under_review', 'interview');
    v_recruitment_count := v_count;
    if v_count > 0 then
      v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
        'kind', 'recruitment', 'count', v_count,
        'href', '/administrativo/pendencias#recrutamento',
        'label', 'Candidaturas aguardando análise', 'tone', 'normal'
      ));
    end if;
    v_management_pending := v_management_pending + v_count;
  end if;

  if 'hr.absences.review' = any(v_permissions) then
    select count(*)::integer into v_count
    from public.rh_absence_requests absence where absence.status = 'pending';
    if v_count > 0 then
      v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
        'kind', 'absence', 'count', v_count,
        'href', '/administrativo/pendencias#ausencias',
        'label', 'Afastamentos aguardando análise', 'tone', 'important'
      ));
    end if;
    v_management_pending := v_management_pending + v_count;
  end if;

  if 'hr.justifications.review' = any(v_permissions) then
    select count(*)::integer into v_count
    from public.rh_hour_justifications justification where justification.status = 'pending';
    if v_count > 0 then
      v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
        'kind', 'hour_justification', 'count', v_count,
        'href', '/administrativo/pendencias#ausencias',
        'label', 'Justificativas de horas aguardando análise', 'tone', 'important'
      ));
    end if;
    v_management_pending := v_management_pending + v_count;
  end if;

  if 'hr.discipline.manage' = any(v_permissions) or 'hr.discipline.review' = any(v_permissions) then
    select count(*)::integer into v_count
    from public.rh_disciplinary_reviews review where review.status = 'pending';
    if v_count > 0 then
      v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
        'kind', 'discipline', 'count', v_count,
        'href', '/administrativo/pendencias#disciplina',
        'label', 'Análises disciplinares pendentes', 'tone', 'urgent'
      ));
    end if;
    v_management_pending := v_management_pending + v_count;
  end if;

  if 'progression.review' = any(v_permissions) then
    select count(*)::integer into v_count
    from public.staff_promotion_reviews review where review.status = 'pending';
    if v_count > 0 then
      v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
        'kind', 'career', 'count', v_count,
        'href', '/administrativo/pendencias#carreira',
        'label', 'Promoções aguardando decisão', 'tone', 'important'
      ));
    end if;
    v_management_pending := v_management_pending + v_count;
  end if;

  if 'healthplans.review' = any(v_permissions) then
    select count(*)::integer into v_count
    from public.patient_health_plan_requests request where request.status = 'pending';
    if v_count > 0 then
      v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
        'kind', 'health_plan', 'count', v_count,
        'href', '/administrativo/pendencias#planos-saude',
        'label', 'Planos aguardando confirmação', 'tone', 'important'
      ));
    end if;
    v_management_pending := v_management_pending + v_count;
  end if;

  if 'casts.view' = any(v_permissions) and 'casts.manage' = any(v_permissions) then
    select count(*)::integer into v_count
    from public.clinical_casts cast_record
    where cast_record.status = 'in_use'
      and cast_record.expected_removal_at <= now();
    if v_count > 0 then
      v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
        'kind', 'cast', 'count', v_count,
        'href', '/administrativo/pendencias#gessos',
        'label', 'Gessos com retirada prevista ultrapassada', 'tone', 'urgent'
      ));
    end if;
    v_management_pending := v_management_pending + v_count;
  end if;

  v_attention_total := v_attention_total + v_management_pending;

  -- Três comunicados compactos. O corpo não integra o payload do Dashboard.
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', announcement.id,
    'title', announcement.title,
    'priority', announcement.priority,
    'action_url', announcement.action_url,
    'created_at', announcement.created_at,
    'author_name', announcement.author_name,
    'read_at', announcement.read_at
  ) order by announcement.unread desc, announcement.created_at desc, announcement.id desc), '[]'::jsonb)
  into v_announcements
  from (
    select
      notification.id,
      notification.title,
      notification.priority,
      notification.action_url,
      notification.created_at,
      coalesce(author.display_name, 'Sistema HPSM') as author_name,
      read.read_at,
      (read.read_at is null) as unread
    from public.notifications notification
    left join public.notification_reads read
      on read.notification_id = notification.id and read.user_id = v_actor
    left join public.profiles author on author.user_id = notification.created_by
    where notification.kind = 'announcement'
      and notification.archived_at is null
      and (notification.expires_at is null or notification.expires_at > now())
      and (
        notification.recipient_id = v_actor
        or notification.audience = 'all'
        or (
          notification.audience = 'directors'
          and case
            when notification.required_permission is not null
              then notification.required_permission = any(v_permissions)
            else 'hr.team.view' = any(v_permissions)
          end
        )
        or (
          notification.audience = 'employees'
          and not ('hr.team.view' = any(v_permissions))
        )
      )
    order by (read.read_at is null) desc, notification.created_at desc, notification.id desc
    limit 3
  ) announcement;

  -- A visão gerencial só nasce para quem pode abrir Relatórios e reutiliza
  -- diretamente o agregador canônico da Fase 8, inclusive permissões parciais.
  if 'hr.reports.view' = any(v_permissions) then
    v_hospital := public.hpsm_report_overview(v_week_start, v_week_end)
      || jsonb_build_object('pending_count', v_management_pending)
      || case when 'recruitment.manage' = any(v_permissions)
        then jsonb_build_object('recruitment_pending', v_recruitment_count)
        else '{}'::jsonb
      end;
  end if;

  return jsonb_build_object(
    'period', jsonb_build_object('start', v_week_start, 'end', v_week_end),
    'weekly_inputs', v_weekly_inputs,
    'production', v_production,
    'career', v_career,
    'attention', jsonb_build_object('total', v_attention_total, 'items', v_attention_items),
    'announcements', v_announcements,
    'hospital', v_hospital
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_global_search(p_query text, p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[] := public.effective_permission_codes(v_actor);
  v_query text := btrim(coalesce(p_query, ''));
  v_limit integer := least(greatest(coalesce(p_limit, 5), 1), 5);
  v_escaped text;
  v_contains text;
  v_prefix text;
  v_result jsonb;
begin
  if char_length(v_query) < 2 then
    return jsonb_build_object('items', '[]'::jsonb);
  end if;
  if char_length(v_query) > 100 then
    raise exception 'A busca deve ter no máximo 100 caracteres.' using errcode = '22023';
  end if;

  -- Escapa curingas fornecidos pelo usuário antes de montar os padrões ILIKE.
  v_escaped := replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_');
  v_contains := '%' || v_escaped || '%';
  v_prefix := v_escaped || '%';

  with
  patient_results as (
    select
      1 as category_order,
      case
        when upper(patient.passport) = upper(v_query) then 1
        when patient.passport ilike v_prefix escape '\' then 2
        when lower(patient.name) = lower(v_query) then 3
        when patient.name ilike v_prefix escape '\' then 4
        else 5
      end as score,
      patient.updated_at as sort_at,
      'patients'::text as category,
      patient.id::text as id,
      patient.name as title,
      'Passaporte ' || patient.passport as subtitle,
      '/pacientes/' || patient.id::text as href,
      null::numeric as amount
    from public.patients patient
    where 'patients.view' = any(v_permissions)
      and (
        patient.passport ilike v_contains escape '\'
        or patient.name ilike v_contains escape '\'
      )
    order by score, patient.updated_at desc, patient.name
    limit v_limit
  ),
  professional_results as (
    select
      2 as category_order,
      case
        when upper(profile.passport) = upper(v_query) then 1
        when profile.passport ilike v_prefix escape '\' then 2
        when lower(profile.display_name) = lower(v_query) then 3
        when profile.display_name ilike v_prefix escape '\' then 4
        when lower(coalesce(position.name, '')) = lower(v_query) then 5
        when coalesce(position.name, '') ilike v_prefix escape '\' then 6
        else 7
      end as score,
      profile.updated_at as sort_at,
      'professionals'::text as category,
      profile.user_id::text as id,
      profile.display_name as title,
      profile.passport || ' · ' || coalesce(position.name, 'Sem cargo atual') as subtitle,
      '/administrativo/perfis?selecionar=' || profile.user_id::text as href,
      null::numeric as amount
    from public.profiles profile
    left join public.staff_positions position on position.id = profile.position_id
    where v_permissions && array['hr.team.view', 'hr.reports.view', 'team.manage', 'access.manage']::text[]
      and (
        profile.passport ilike v_contains escape '\'
        or profile.display_name ilike v_contains escape '\'
        or coalesce(position.name, '') ilike v_contains escape '\'
      )
    order by score, profile.updated_at desc, profile.display_name
    limit v_limit
  ),
  attendance_results as (
    select
      3 as category_order,
      case
        when v_query ~ '^[0-9]+$' and attendance.id::text = v_query then 1
        when v_query ~ '^[0-9]+$' and attendance.id::text like v_query || '%' then 2
        when upper(patient.passport) = upper(v_query) then 3
        when patient.passport ilike v_prefix escape '\' then 4
        when lower(patient.name) = lower(v_query) then 5
        when patient.name ilike v_prefix escape '\' then 6
        else 7
      end as score,
      attendance.created_at as sort_at,
      'attendances'::text as category,
      attendance.id::text as id,
      coalesce(nullif(btrim(attendance.patient_name), ''), 'Venda avulsa') as title,
      'Atendimento #' || attendance.id::text || ' · ' || attendance.patient_passport
        || ' · ' || to_char(attendance.created_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') as subtitle,
      '/atendimentos#atendimento-' || attendance.id::text as href,
      attendance.total as amount
    from public.attendances attendance
    join public.patients patient on patient.id = attendance.patient_id
    where (
        'attendances.create' = any(v_permissions)
        or 'attendances.manage' = any(v_permissions)
        or 'patients.view' = any(v_permissions)
      )
      and (
        attendance.performed_by = v_actor
        or 'attendances.manage' = any(v_permissions)
        or 'patients.view' = any(v_permissions)
      )
      and (
        (v_query ~ '^[0-9]+$' and attendance.id::text like v_query || '%')
        or patient.passport ilike v_contains escape '\'
        or patient.name ilike v_contains escape '\'
      )
    order by score, attendance.created_at desc, attendance.id desc
    limit v_limit
  ),
  catalog_results as (
    select
      4 as category_order,
      case
        when lower(service.name) = lower(v_query) then 1
        when service.name ilike v_prefix escape '\' then 2
        when lower(service.category) = lower(v_query) then 3
        when service.category ilike v_prefix escape '\' then 4
        else 5
      end as score,
      service.updated_at as sort_at,
      'catalog'::text as category,
      service.id::text as id,
      service.name as title,
      service.category || ' · ' || case when service.active then 'Ativo' else 'Inativo' end as subtitle,
      '/catalogo?item=' || service.id::text as href,
      service.unit_price as amount
    from public.service_catalog service
    where 'catalog.manage' = any(v_permissions)
      and (
        service.name ilike v_contains escape '\'
        or service.category ilike v_contains escape '\'
      )
    order by score, service.updated_at desc, service.name
    limit v_limit
  ),
  application_results as (
    select
      5 as category_order,
      case
        when upper(application.passport) = upper(v_query) then 1
        when application.passport ilike v_prefix escape '\' then 2
        when lower(application.full_name) = lower(v_query) then 3
        when application.full_name ilike v_prefix escape '\' then 4
        else 5
      end as score,
      application.created_at as sort_at,
      'applications'::text as category,
      application.id::text as id,
      application.full_name as title,
      application.passport || ' · ' || case application.status
        when 'submitted' then 'Recebida'
        when 'under_review' then 'Em análise'
        when 'interview' then 'Entrevista'
        when 'approved' then 'Aprovada'
        when 'rejected' then 'Recusada'
        when 'withdrawn' then 'Retirada'
        else 'Situação não informada'
      end as subtitle,
      '/administrativo/recrutamento?selecionar=' || application.id::text as href,
      null::numeric as amount
    from public.recruitment_applications application
    where 'recruitment.manage' = any(v_permissions)
      and (
        application.passport ilike v_contains escape '\'
        or application.full_name ilike v_contains escape '\'
      )
    order by score, application.created_at desc, application.full_name
    limit v_limit
  ),
  combined as (
    select * from patient_results
    union all select * from professional_results
    union all select * from attendance_results
    union all select * from catalog_results
    union all select * from application_results
  )
  select jsonb_build_object(
    'items', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'amount', combined.amount,
          'category', combined.category,
          'href', combined.href,
          'id', combined.id,
          'subtitle', combined.subtitle,
          'title', combined.title
        )
        order by combined.category_order, combined.score, combined.sort_at desc, combined.title
      ),
      '[]'::jsonb
    )
  ) into v_result
  from combined;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_hr_production(p_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_month_start date;
  v_month_last date;
  v_range_start date;
  v_range_end date;
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_month is null or p_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Competência inválida.' using errcode = '22023';
  end if;

  v_month_start := to_date(p_month || '-01', 'YYYY-MM-DD');
  if to_char(v_month_start, 'YYYY-MM') <> p_month then
    raise exception 'Competência inválida.' using errcode = '22023';
  end if;

  v_month_last := (v_month_start + interval '1 month - 1 day')::date;
  v_range_start := v_month_start - (extract(isodow from v_month_start)::integer - 1);
  v_range_end := v_month_last + (8 - extract(isodow from v_month_last)::integer);

  select jsonb_build_object(
    'month', p_month,
    'days', coalesce(jsonb_agg(
      jsonb_build_object(
        'employee_id', grouped.employee_id,
        'date', grouped.work_date,
        'attendance_count', grouped.attendance_count,
        'total_amount', grouped.total_amount
      ) order by grouped.work_date, grouped.employee_id
    ), '[]'::jsonb)
  )
  into v_result
  from (
    select
      attendance.performed_by as employee_id,
      (attendance.created_at at time zone 'America/Sao_Paulo')::date as work_date,
      count(*)::integer as attendance_count,
      coalesce(sum(attendance.total), 0) as total_amount
    from public.attendances attendance
    where attendance.status = 'completed'
      and attendance.created_at >= (v_range_start::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < (v_range_end::timestamp at time zone 'America/Sao_Paulo')
    group by attendance.performed_by, (attendance.created_at at time zone 'America/Sao_Paulo')::date
  ) grouped;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_my_hr_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_result jsonb;
begin
  select jsonb_build_object(
    'positions', (
      select coalesce(jsonb_agg(to_jsonb(position) order by position.level), '[]'::jsonb)
      from public.staff_positions position
    ),
    'history', (
      select coalesce(jsonb_agg(to_jsonb(history) order by history.effective_at desc), '[]'::jsonb)
      from (
        select source.*
        from public.staff_position_history source
        where source.employee_id = v_actor
        order by source.effective_at desc
        limit 100
      ) history
    ),
    'progression', coalesce(private.get_staff_progression_status(v_actor), '{}'::jsonb),
    'courses', (
      select coalesce(jsonb_agg(to_jsonb(course) order by course.active desc, course.name), '[]'::jsonb)
      from public.courses course
    ),
    'courseRecords', (
      select coalesce(jsonb_agg(to_jsonb(record) order by record.assigned_at desc), '[]'::jsonb)
      from (
        select source.*
        from public.staff_course_records source
        where source.employee_id = v_actor
        order by source.assigned_at desc
        limit 200
      ) record
    ),
    'snapshots', (
      select coalesce(jsonb_agg(to_jsonb(snapshot) order by snapshot.reading_date), '[]'::jsonb)
      from public.rh_hour_snapshots snapshot
      where snapshot.employee_id = v_actor
    ),
    'absences', (
      select coalesce(jsonb_agg(to_jsonb(absence) order by absence.requested_at desc), '[]'::jsonb)
      from (
        select source.*
        from public.rh_absence_requests source
        where source.employee_id = v_actor
        order by source.requested_at desc
        limit 100
      ) absence
    ),
    'leaveAdjustments', (
      select coalesce(jsonb_agg(to_jsonb(adjustment) order by adjustment.week_start desc), '[]'::jsonb)
      from (
        select source.*
        from public.rh_leave_week_adjustments source
        where source.employee_id = v_actor
        order by source.week_start desc
        limit 250
      ) adjustment
    ),
    'weeklyRecords', (
      select coalesce(jsonb_agg(to_jsonb(record) order by record.week_start desc), '[]'::jsonb)
      from (
        select source.*
        from public.rh_weekly_records source
        where source.employee_id = v_actor
        order by source.week_start desc
        limit 100
      ) record
    ),
    'hourJustifications', (
      select coalesce(jsonb_agg(to_jsonb(justification) order by justification.submitted_at desc), '[]'::jsonb)
      from (
        select source.*
        from public.rh_hour_justifications source
        where source.employee_id = v_actor
        order by source.submitted_at desc
        limit 100
      ) justification
    ),
    'warnings', (
      select coalesce(jsonb_agg(to_jsonb(warning) order by warning.issued_at desc), '[]'::jsonb)
      from (
        select source.*
        from public.rh_warnings source
        where source.employee_id = v_actor
        order by source.issued_at desc
        limit 100
      ) warning
    )
  ) into v_result;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_operational_catalog()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[] := public.effective_permission_codes(v_actor);
  v_result jsonb;
begin
  if not (
    'catalog.view' = any(v_permissions)
    or 'catalog.manage' = any(v_permissions)
    or 'attendances.create' = any(v_permissions)
    or 'attendances.manage' = any(v_permissions)
  ) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', service.id,
        'code', service.code,
        'icon', service.icon,
        'image_path', service.image_path,
        'name', service.name,
        'category', service.category,
        'unit_price', service.unit_price,
        'active', service.active,
        'sort_order', service.sort_order,
        'created_at', service.created_at,
        'updated_at', service.updated_at,
        'plan_discounts', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'plan_code', discount.plan_code,
              'discount_percent', discount.discount_percent
            )
            order by discount.plan_code
          )
          from public.plan_discounts discount
          where discount.service_id = service.id
        ), '[]'::jsonb)
      )
      order by service.sort_order asc, service.name asc
    ),
    '[]'::jsonb
  )
  into v_result
  from public.service_catalog service;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_partnership_detail(p_partnership_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.view');
  v_result jsonb;
begin
  select jsonb_build_object(
    'found', true,
    'partnership', jsonb_build_object(
      'id', partnership.id,
      'name', partnership.name,
      'status', partnership.status,
      'notes', partnership.notes,
      'responsible', case when patient.id is null then null else jsonb_build_object(
        'id', patient.id, 'name', patient.name, 'passport', patient.passport,
        'portal_ready', patient.birth_date is not null
      ) end,
      'created_at', partnership.created_at,
      'updated_at', partnership.updated_at,
      'deactivated_at', partnership.deactivated_at,
      'deactivation_reason', partnership.deactivation_reason
    ),
    'metrics', jsonb_build_object(
      'linked', (select count(*) from public.patient_partnerships membership where membership.partnership_id = partnership.id and membership.status = 'active'),
      'pending_registration', (select count(*) from public.partnership_pending_beneficiaries pending where pending.partnership_id = partnership.id and pending.status = 'pending_registration'),
      'name_review', (select count(*) from public.partnership_pending_beneficiaries pending where pending.partnership_id = partnership.id and pending.status = 'name_review')
    )
  ) into v_result
  from public.partnerships partnership
  left join public.patients patient on patient.id = partnership.responsible_patient_id
  where partnership.id = p_partnership_id;

  return coalesce(v_result, jsonb_build_object('found', false));
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_partnership_member_page(p_partnership_id bigint, p_filter text DEFAULT 'all'::text, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.view');
  v_filter text := lower(btrim(coalesce(p_filter, 'all')));
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if v_filter not in ('all', 'linked', 'pending_registration', 'name_review') then
    raise exception 'Filtro de beneficiários inválido.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.partnerships where id = p_partnership_id) then
    raise exception 'Parceria não localizada.' using errcode = '22023';
  end if;

  with combined as materialized (
    select
      'membership'::text as record_type,
      membership.id,
      patient.id as patient_id,
      patient.passport,
      patient.name,
      'linked'::text as status,
      membership.linked_at as occurred_at,
      membership.linked_by_type as origin,
      null::text as canonical_name
    from public.patient_partnerships membership
    join public.patients patient on patient.id = membership.patient_id
    where membership.partnership_id = p_partnership_id and membership.status = 'active'
    union all
    select
      'pending'::text,
      pending.id,
      canonical.id,
      pending.passport,
      pending.informed_name,
      pending.status,
      pending.created_at,
      pending.created_by_type,
      case when pending.status = 'name_review' then canonical.name else null end
    from public.partnership_pending_beneficiaries pending
    left join public.patients canonical on canonical.passport = pending.passport
    where pending.partnership_id = p_partnership_id
      and pending.status in ('pending_registration', 'name_review')
  ), filtered as (
    select * from combined row
    where (v_filter = 'all' or row.status = v_filter)
      and (v_search = '' or lower(row.name) like '%' || v_search || '%' or row.passport like v_search || '%')
  ), page_rows as (
    select * from filtered row
    order by lower(row.name), row.passport, row.record_type, row.id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'record_type', row.record_type,
      'id', row.id,
      'patient_id', row.patient_id,
      'passport', row.passport,
      'name', row.name,
      'status', row.status,
      'occurred_at', row.occurred_at,
      'origin', row.origin,
      'canonical_name', row.canonical_name
    ) order by lower(row.name), row.passport, row.record_type, row.id), '[]'::jsonb),
    'total', (select count(*)::integer from filtered),
    'limit', v_limit,
    'offset', v_offset
  ) into v_result
  from page_rows row;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_partnership_page(p_status text DEFAULT 'active'::text, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 24, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.view');
  v_status text := lower(btrim(coalesce(p_status, 'active')));
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_limit integer := least(greatest(coalesce(p_limit, 24), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if v_status not in ('active', 'inactive') then raise exception 'Status de parceria inválido.' using errcode = '22023'; end if;

  with filtered as materialized (
    select partnership.*
    from public.partnerships partnership
    where partnership.status = v_status
      and (v_search = '' or lower(partnership.name) like '%' || v_search || '%')
  ), member_counts as materialized (
    select membership.partnership_id, count(*)::integer as linked
    from public.patient_partnerships membership
    join filtered partnership on partnership.id = membership.partnership_id
    where membership.status = 'active'
    group by membership.partnership_id
  ), pending_counts as materialized (
    select pending.partnership_id,
      count(*) filter (where pending.status = 'pending_registration')::integer as pending_registration,
      count(*) filter (where pending.status = 'name_review')::integer as name_review
    from public.partnership_pending_beneficiaries pending
    join filtered partnership on partnership.id = pending.partnership_id
    where pending.status in ('pending_registration', 'name_review')
    group by pending.partnership_id
  ), page_rows as (
    select partnership.*, patient.name as responsible_name, patient.passport as responsible_passport,
      coalesce(member_counts.linked, 0) as linked,
      coalesce(pending_counts.pending_registration, 0) as pending_registration,
      coalesce(pending_counts.name_review, 0) as name_review
    from filtered partnership
    left join public.patients patient on patient.id = partnership.responsible_patient_id
    left join member_counts on member_counts.partnership_id = partnership.id
    left join pending_counts on pending_counts.partnership_id = partnership.id
    order by lower(partnership.name), partnership.id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', row.id,
      'name', row.name,
      'status', row.status,
      'responsible', case when row.responsible_patient_id is null then null else jsonb_build_object(
        'id', row.responsible_patient_id, 'name', row.responsible_name, 'passport', row.responsible_passport
      ) end,
      'linked', row.linked,
      'pending_registration', row.pending_registration,
      'name_review', row.name_review,
      'total_informed', row.linked + row.pending_registration + row.name_review,
      'created_at', row.created_at,
      'updated_at', row.updated_at
    ) order by lower(row.name), row.id), '[]'::jsonb),
    'total', (select count(*)::integer from filtered),
    'limit', v_limit,
    'offset', v_offset
  ) into v_result
  from page_rows row;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_partnership_patient_lookup(p_search text, p_limit integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_limit integer := least(greatest(coalesce(p_limit, 8), 1), 12);
  v_result jsonb;
begin
  if char_length(v_search) < 1 then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', patient.id,
    'name', patient.name,
    'passport', patient.passport,
    'portal_ready', patient.birth_date is not null
  ) order by (patient.passport = v_search) desc, patient.passport, patient.name), '[]'::jsonb)
  into v_result
  from (
    select patient.*
    from public.patients patient
    where patient.passport like v_search || '%'
       or lower(patient.name) like '%' || v_search || '%'
    order by (patient.passport = v_search) desc, patient.passport, patient.name
    limit v_limit
  ) patient;
  return v_result;
end;
$function$;


CREATE OR REPLACE FUNCTION public.hpsm_report_financial(p_start_date date, p_end_date date, p_employee_id uuid, p_position_id bigint, p_sort text, p_direction text, p_page integer, p_page_size integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_sort text := coalesce(nullif(p_sort, ''), 'value');
  v_direction text := coalesce(nullif(p_direction, ''), 'desc');
  v_page integer := greatest(1, coalesce(p_page, 1));
  v_page_size integer := least(100, greatest(1, coalesce(p_page_size, 25)));
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view')
     or not private.has_permission(v_actor, 'attendances.manage') then
    raise exception 'Acesso financeiro não autorizado.' using errcode = '42501';
  end if;
  perform private.hpsm_report_validate_period(p_start_date, p_end_date);
  if v_sort not in ('name', 'attendances', 'items', 'value') or v_direction not in ('asc', 'desc') then
    raise exception 'Ordenação inválida.' using errcode = '22023';
  end if;

  with filtered_attendances as (
    select attendance.*, profile.display_name, profile.passport, profile.position_id,
      coalesce(position.name, 'Cargo não informado') as position_name
    from public.attendances attendance
    join public.profiles profile on profile.user_id = attendance.performed_by
    left join public.staff_positions position on position.id = profile.position_id
    where attendance.status = 'completed'
      and attendance.created_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')
      and (p_employee_id is null or attendance.performed_by = p_employee_id)
      and (p_position_id is null or profile.position_id = p_position_id)
  ), item_by_attendance as (
    select item.attendance_id, coalesce(sum(item.quantity), 0)::integer as item_count
    from public.attendance_items item
    join filtered_attendances attendance on attendance.id = item.attendance_id
    group by item.attendance_id
  ), production as (
    select
      attendance.performed_by as employee_id,
      attendance.display_name,
      attendance.passport,
      attendance.position_id,
      attendance.position_name,
      count(*)::integer as attendance_count,
      coalesce(sum(item.item_count), 0)::integer as item_count,
      coalesce(sum(attendance.total), 0) as total_amount,
      case when count(*) = 0 then 0 else round(sum(attendance.total) / count(*), 2) end as ticket_average
    from filtered_attendances attendance
    left join item_by_attendance item on item.attendance_id = attendance.id
    group by attendance.performed_by, attendance.display_name, attendance.passport, attendance.position_id, attendance.position_name
  ), ordered as (
    select production.*,
      row_number() over (order by
        case when v_sort = 'name' and v_direction = 'asc' then display_name end asc,
        case when v_sort = 'name' and v_direction = 'desc' then display_name end desc,
        case when v_sort = 'attendances' and v_direction = 'asc' then attendance_count end asc,
        case when v_sort = 'attendances' and v_direction = 'desc' then attendance_count end desc,
        case when v_sort = 'items' and v_direction = 'asc' then item_count end asc,
        case when v_sort = 'items' and v_direction = 'desc' then item_count end desc,
        case when v_sort = 'value' and v_direction = 'asc' then total_amount end asc,
        case when v_sort = 'value' and v_direction = 'desc' then total_amount end desc,
        display_name asc, employee_id asc
      ) as row_number
    from production
  ), paged as (
    select * from ordered
    where row_number > (v_page - 1) * v_page_size and row_number <= v_page * v_page_size
  ), totals as (
    select
      count(*)::integer as attendance_count,
      coalesce(sum(attendance.total), 0) as total_amount,
      coalesce(sum(item.item_count), 0)::integer as item_count,
      count(distinct attendance.performed_by)::integer as professional_count,
      count(distinct attendance.patient_id) filter (where attendance.patient_id is not null)::integer as unique_patients
    from filtered_attendances attendance
    left join item_by_attendance item on item.attendance_id = attendance.id
  ), top_items as (
    select
      item.service_id,
      item.service_name,
      coalesce(catalog.category, 'Sem categoria') as category,
      sum(item.quantity)::integer as quantity,
      coalesce(sum(item.line_total), 0) as total_amount
    from public.attendance_items item
    join filtered_attendances attendance on attendance.id = item.attendance_id
    left join public.service_catalog catalog on catalog.id = item.service_id
    group by item.service_id, item.service_name, catalog.category
    order by sum(item.quantity) desc, sum(item.line_total) desc, item.service_name
    limit 10
  ), benefits as (
    select
      coalesce(attendance.plan_code, 'none') as code,
      coalesce(max(attendance.plan_name), 'Sem benefício') as name,
      count(*)::integer as attendance_count,
      coalesce(sum(attendance.total), 0) as total_amount,
      coalesce(sum(attendance.discount), 0) as discount_amount
    from filtered_attendances attendance
    group by attendance.plan_code
    order by count(*) desc, coalesce(attendance.plan_code, 'none')
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'attendance_count', totals.attendance_count,
      'total_amount', totals.total_amount,
      'ticket_average', case when totals.attendance_count = 0 then 0 else round(totals.total_amount / totals.attendance_count, 2) end,
      'item_count', totals.item_count,
      'professional_count', totals.professional_count,
      'unique_patients', totals.unique_patients
    ),
    'production', coalesce((select jsonb_agg(jsonb_build_object(
      'employee_id', item.employee_id,
      'name', item.display_name,
      'passport', item.passport,
      'position_id', item.position_id,
      'position', item.position_name,
      'attendance_count', item.attendance_count,
      'item_count', item.item_count,
      'total_amount', item.total_amount,
      'ticket_average', item.ticket_average
    ) order by item.row_number) from paged item), '[]'::jsonb),
    'production_total', (select count(*)::integer from production),
    'page', v_page,
    'page_size', v_page_size,
    'top_items', coalesce((select jsonb_agg(jsonb_build_object(
      'service_id', item.service_id,
      'name', item.service_name,
      'category', item.category,
      'quantity', item.quantity,
      'total_amount', item.total_amount
    ) order by item.quantity desc, item.total_amount desc, item.service_name) from top_items item), '[]'::jsonb),
    'benefits', coalesce((select jsonb_agg(jsonb_build_object(
      'code', benefit.code,
      'name', benefit.name,
      'attendance_count', benefit.attendance_count,
      'total_amount', benefit.total_amount,
      'discount_amount', benefit.discount_amount
    ) order by benefit.attendance_count desc, benefit.code) from benefits benefit), '[]'::jsonb),
    'positions', coalesce((select jsonb_agg(jsonb_build_object('id', position.id, 'name', position.name) order by position.sort_order, position.name)
      from public.staff_positions position where position.active), '[]'::jsonb)
  ) into v_result
  from totals;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_report_hr(p_start_date date, p_end_date date, p_position_id bigint, p_status text, p_search text, p_sort text, p_direction text, p_page integer, p_page_size integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_status text := coalesce(nullif(p_status, ''), 'active');
  v_search text := btrim(coalesce(p_search, ''));
  v_sort text := coalesce(nullif(p_sort, ''), 'name');
  v_direction text := coalesce(nullif(p_direction, ''), 'asc');
  v_page integer := greatest(1, coalesce(p_page, 1));
  v_page_size integer := least(100, greatest(1, coalesce(p_page_size, 25)));
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  perform private.hpsm_report_validate_period(p_start_date, p_end_date);
  if v_status not in ('all', 'active', 'suspended')
     or v_sort not in ('name', 'position', 'hours', 'difference', 'status')
     or v_direction not in ('asc', 'desc')
     or char_length(v_search) > 80 then
    raise exception 'Filtros inválidos.' using errcode = '22023';
  end if;

  with hours as (
    select * from private.hpsm_report_hours(p_start_date, p_end_date)
  ), goals as (
    select
      record.employee_id,
      count(*)::integer as recorded_weeks,
      coalesce(sum(record.base_required_minutes), 0)::bigint as base_target_minutes,
      coalesce(sum(record.leave_deduction_minutes), 0)::bigint as leave_minutes,
      coalesce(sum(record.required_minutes), 0)::bigint as effective_target_minutes,
      count(*) filter (where record.required_minutes = 0)::integer as excused_weeks,
      count(*) filter (where record.required_minutes > 0 and record.remaining_deficit_minutes = 0)::integer as met_weeks,
      count(*) filter (where record.remaining_deficit_minutes > 0)::integer as below_weeks
    from public.rh_weekly_records record
    where record.week_start <= p_end_date and record.week_end >= p_start_date
    group by record.employee_id
  ), rows as (
    select
      profile.user_id,
      profile.display_name,
      profile.passport,
      profile.position_id,
      coalesce(position.name, 'Cargo não informado') as position_name,
      profile.status,
      coalesce(hours.worked_minutes, 0)::bigint as worked_minutes,
      coalesce(goals.base_target_minutes, 0)::bigint as base_target_minutes,
      coalesce(goals.leave_minutes, 0)::bigint as leave_minutes,
      coalesce(goals.effective_target_minutes, 0)::bigint as effective_target_minutes,
      (coalesce(hours.worked_minutes, 0) - coalesce(goals.effective_target_minutes, 0))::bigint as difference_minutes,
      coalesce(goals.recorded_weeks, 0)::integer as recorded_weeks,
      coalesce(goals.met_weeks, 0)::integer as met_weeks,
      coalesce(goals.below_weeks, 0)::integer as below_weeks,
      coalesce(goals.excused_weeks, 0)::integer as excused_weeks,
      case
        when coalesce(goals.recorded_weeks, 0) = 0 then 'no_data'
        when goals.below_weeks > 0 then 'below'
        when goals.excused_weeks > 0 and goals.met_weeks = 0 then 'fully_excused'
        else 'met'
      end as goal_status,
      exists (
        select 1 from public.rh_absence_requests absence
        where absence.employee_id = profile.user_id and absence.status = 'approved'
          and absence.start_date <= p_end_date and absence.end_date >= p_start_date
      ) as has_absence,
      exists (
        select 1 from public.rh_hour_justifications justification
        join public.rh_weekly_records weekly on weekly.id = justification.weekly_record_id
        where justification.employee_id = profile.user_id
          and weekly.week_start <= p_end_date and weekly.week_end >= p_start_date
      ) as has_justification,
      (
        select count(*)::integer from public.rh_warnings warning
        where warning.employee_id = profile.user_id and warning.status = 'active'
          and warning.cycle_month between pg_catalog.date_trunc('month', p_start_date::timestamp)::date
            and pg_catalog.date_trunc('month', p_end_date::timestamp)::date
      ) as active_warnings
    from public.profiles profile
    left join public.staff_positions position on position.id = profile.position_id
    left join hours on hours.employee_id = profile.user_id
    left join goals on goals.employee_id = profile.user_id
    where profile.role_code <> 'diretor_geral'
      and profile.status <> 'inactive'
  ), filtered as (
    select * from rows
    where (v_status = 'all' or status = v_status)
      and (p_position_id is null or position_id = p_position_id)
      and (v_search = '' or passport like '%' || v_search || '%' or lower(display_name) like '%' || lower(v_search) || '%')
  ), ordered as (
    select filtered.*,
      row_number() over (order by
        case when v_sort = 'name' and v_direction = 'asc' then display_name end asc,
        case when v_sort = 'name' and v_direction = 'desc' then display_name end desc,
        case when v_sort = 'position' and v_direction = 'asc' then position_name end asc,
        case when v_sort = 'position' and v_direction = 'desc' then position_name end desc,
        case when v_sort = 'hours' and v_direction = 'asc' then worked_minutes end asc,
        case when v_sort = 'hours' and v_direction = 'desc' then worked_minutes end desc,
        case when v_sort = 'difference' and v_direction = 'asc' then difference_minutes end asc,
        case when v_sort = 'difference' and v_direction = 'desc' then difference_minutes end desc,
        case when v_sort = 'status' and v_direction = 'asc' then goal_status end asc,
        case when v_sort = 'status' and v_direction = 'desc' then goal_status end desc,
        display_name asc, user_id asc
      ) as row_number
    from filtered
  ), paged as (
    select * from ordered
    where row_number > (v_page - 1) * v_page_size
      and row_number <= v_page * v_page_size
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', item.user_id,
      'name', item.display_name,
      'passport', item.passport,
      'position_id', item.position_id,
      'position', item.position_name,
      'profile_status', item.status,
      'worked_minutes', item.worked_minutes,
      'base_target_minutes', item.base_target_minutes,
      'leave_minutes', item.leave_minutes,
      'effective_target_minutes', item.effective_target_minutes,
      'difference_minutes', item.difference_minutes,
      'recorded_weeks', item.recorded_weeks,
      'met_weeks', item.met_weeks,
      'below_weeks', item.below_weeks,
      'excused_weeks', item.excused_weeks,
      'goal_status', item.goal_status,
      'has_absence', item.has_absence,
      'has_justification', item.has_justification,
      'active_warnings', item.active_warnings
    ) order by item.row_number) from paged item), '[]'::jsonb),
    'total', (select count(*)::integer from filtered),
    'page', v_page,
    'page_size', v_page_size,
    'positions', coalesce((select jsonb_agg(jsonb_build_object('id', position.id, 'name', position.name) order by position.sort_order, position.name)
      from public.staff_positions position where position.active), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_report_individual(p_start_date date, p_end_date date, p_employee_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_financial boolean;
  v_courses boolean;
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  perform private.hpsm_report_validate_period(p_start_date, p_end_date);
  if p_employee_id is null then raise exception 'Selecione um profissional.' using errcode = '22023'; end if;
  v_financial := private.has_permission(v_actor, 'attendances.manage');
  v_courses := private.has_permission(v_actor, 'courses.view');

  with employee as (
    select profile.user_id, profile.display_name, profile.passport, profile.status, profile.position_id,
      coalesce(position.name, 'Cargo não informado') as position_name
    from public.profiles profile
    left join public.staff_positions position on position.id = profile.position_id
    where profile.user_id = p_employee_id and profile.role_code <> 'diretor_geral'
  ), hours as (
    select coalesce(sum(value.worked_minutes), 0)::bigint as worked_minutes
    from private.hpsm_report_hours(p_start_date, p_end_date) value where value.employee_id = p_employee_id
  ), goals as (
    select
      count(*)::integer as recorded_weeks,
      coalesce(sum(record.base_required_minutes), 0)::bigint as base_target_minutes,
      coalesce(sum(record.leave_deduction_minutes), 0)::bigint as leave_minutes,
      coalesce(sum(record.required_minutes), 0)::bigint as effective_target_minutes,
      count(*) filter (where record.required_minutes = 0)::integer as excused_weeks,
      count(*) filter (where record.required_minutes > 0 and record.remaining_deficit_minutes = 0)::integer as met_weeks,
      count(*) filter (where record.remaining_deficit_minutes > 0)::integer as below_weeks
    from public.rh_weekly_records record
    where record.employee_id = p_employee_id and record.week_start <= p_end_date and record.week_end >= p_start_date
  ), production as (
    select count(*)::integer as attendance_count, coalesce(sum(attendance.total), 0) as total_amount
    from public.attendances attendance
    where v_financial and attendance.performed_by = p_employee_id and attendance.status = 'completed'
      and attendance.created_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')
  ), production_items as (
    select coalesce(sum(item.quantity), 0)::integer as item_count
    from public.attendance_items item
    join public.attendances attendance on attendance.id = item.attendance_id
    where v_financial and attendance.performed_by = p_employee_id and attendance.status = 'completed'
      and attendance.created_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')
  ), rh as (
    select
      (select count(*)::integer from public.rh_warnings warning where warning.employee_id = p_employee_id and warning.status = 'active'
        and warning.cycle_month between pg_catalog.date_trunc('month', p_start_date::timestamp)::date and pg_catalog.date_trunc('month', p_end_date::timestamp)::date) as active_warnings,
      (select count(*)::integer from public.rh_absence_requests absence where absence.employee_id = p_employee_id and absence.status = 'approved'
        and absence.start_date <= p_end_date and absence.end_date >= p_start_date) as absences,
      (select count(*)::integer from public.rh_hour_justifications justification join public.rh_weekly_records weekly on weekly.id = justification.weekly_record_id
        where justification.employee_id = p_employee_id and weekly.week_start <= p_end_date and weekly.week_end >= p_start_date) as justifications
  )
  select jsonb_build_object(
    'found', exists(select 1 from employee),
    'financial_access', v_financial,
    'profile', coalesce((select jsonb_build_object(
      'id', employee.user_id, 'name', employee.display_name, 'passport', employee.passport,
      'position_id', employee.position_id, 'position', employee.position_name, 'status', employee.status
    ) from employee), 'null'::jsonb),
    'period', jsonb_build_object('start', p_start_date, 'end', p_end_date),
    'journey', jsonb_build_object(
      'worked_minutes', hours.worked_minutes,
      'base_target_minutes', goals.base_target_minutes,
      'leave_minutes', goals.leave_minutes,
      'effective_target_minutes', goals.effective_target_minutes,
      'difference_minutes', hours.worked_minutes - goals.effective_target_minutes,
      'recorded_weeks', goals.recorded_weeks,
      'met_weeks', goals.met_weeks,
      'below_weeks', goals.below_weeks,
      'excused_weeks', goals.excused_weeks
    ),
    'rh', jsonb_build_object('active_warnings', rh.active_warnings, 'absences', rh.absences, 'justifications', rh.justifications),
    'production', case when v_financial then jsonb_build_object(
      'attendance_count', production.attendance_count,
      'item_count', production_items.item_count,
      'total_amount', production.total_amount,
      'ticket_average', case when production.attendance_count = 0 then 0 else round(production.total_amount / production.attendance_count, 2) end
    ) else 'null'::jsonb end,
    'career', jsonb_build_object(
      'promotions', coalesce((select jsonb_agg(jsonb_build_object(
        'from_position', coalesce(previous.name, 'Sem cargo anterior'),
        'to_position', current.name,
        'date', (history.effective_at at time zone 'America/Sao_Paulo')::date
      ) order by history.effective_at desc)
        from public.staff_position_history history
        left join public.staff_positions previous on previous.id = history.from_position_id
        join public.staff_positions current on current.id = history.to_position_id
        where history.employee_id = p_employee_id and history.event_type = 'promotion'
          and history.effective_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
          and history.effective_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')), '[]'::jsonb),
      'completed_courses', case when v_courses then (select count(*)::integer from public.staff_course_records course
        where course.employee_id = p_employee_id and course.status = 'completed'
          and course.completed_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
          and course.completed_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')) else null end
    )
  ) into v_result
  from hours cross join goals cross join production cross join production_items cross join rh;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_report_overview(p_start_date date, p_end_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_financial boolean;
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  perform private.hpsm_report_validate_period(p_start_date, p_end_date);
  v_financial := private.has_permission(v_actor, 'attendances.manage');

  with goal_by_employee as (
    select
      record.employee_id,
      count(*) filter (where record.required_minutes = 0) as excused_weeks,
      count(*) filter (where record.required_minutes > 0 and record.remaining_deficit_minutes = 0) as met_weeks,
      count(*) filter (where record.remaining_deficit_minutes > 0) as below_weeks
    from public.rh_weekly_records record
    join public.profiles profile on profile.user_id = record.employee_id and profile.status = 'active'
    where record.week_start <= p_end_date and record.week_end >= p_start_date
    group by record.employee_id
  ), goal_summary as (
    select
      count(*) filter (where goal.below_weeks = 0 and goal.met_weeks > 0)::integer as met_professionals,
      count(*) filter (where goal.below_weeks > 0)::integer as below_professionals,
      count(*) filter (where goal.excused_weeks > 0 and goal.met_weeks = 0 and goal.below_weeks = 0)::integer as fully_excused_professionals
    from goal_by_employee goal
  ), financial as (
    select
      count(*)::integer as attendance_count,
      coalesce(sum(attendance.total), 0) as total_amount,
      count(distinct attendance.patient_id) filter (where attendance.patient_id is not null)::integer as unique_patients,
      count(distinct attendance.performed_by)::integer as participating_professionals
    from public.attendances attendance
    where v_financial
      and attendance.status = 'completed'
      and attendance.created_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')
  )
  select jsonb_build_object(
    'period', jsonb_build_object('start', p_start_date, 'end', p_end_date),
    'financial_access', v_financial,
    'active_professionals', (
      select count(*)::integer from public.profiles profile
      where profile.status = 'active' and profile.role_code <> 'diretor_geral'
    ),
    'hours_minutes', coalesce((select sum(hours.worked_minutes) from private.hpsm_report_hours(p_start_date, p_end_date) hours), 0),
    'met_professionals', coalesce(goal_summary.met_professionals, 0),
    'below_professionals', coalesce(goal_summary.below_professionals, 0),
    'fully_excused_professionals', coalesce(goal_summary.fully_excused_professionals, 0)
  ) || case when v_financial then jsonb_build_object(
    'attendance_count', financial.attendance_count,
    'total_amount', financial.total_amount,
    'ticket_average', case when financial.attendance_count = 0 then 0 else round(financial.total_amount / financial.attendance_count, 2) end,
    'unique_patients', financial.unique_patients,
    'participating_professionals', financial.participating_professionals
  ) else '{}'::jsonb end
  into v_result
  from goal_summary cross join financial;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_report_partnerships(p_start_date date, p_end_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view') or not private.has_permission(v_actor, 'attendances.manage') then
    raise exception 'Acesso financeiro não autorizado.' using errcode = '42501';
  end if;
  perform private.hpsm_report_validate_period(p_start_date, p_end_date);
  select coalesce(jsonb_agg(jsonb_build_object(
    'partnership_id', source.partnership_id,
    'name', source.partnership_name,
    'attendance_count', source.attendance_count,
    'total_amount', source.total_amount,
    'discount_amount', source.discount_amount
  ) order by source.attendance_count desc, source.partnership_name), '[]'::jsonb)
  into v_result
  from (
    select attendance.partnership_id,
      coalesce(attendance.partnership_name, 'Parceria não registrada') as partnership_name,
      count(*)::integer as attendance_count,
      coalesce(sum(attendance.total), 0) as total_amount,
      coalesce(sum(attendance.discount), 0) as discount_amount
    from public.attendances attendance
    where attendance.status = 'completed'
      and attendance.plan_code = 'parceiros_hp'
      and attendance.created_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')
    group by attendance.partnership_id, attendance.partnership_name
  ) source;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_report_staff_search(p_query text, p_limit integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_query text := btrim(coalesce(p_query, ''));
  v_limit integer := least(12, greatest(1, coalesce(p_limit, 8)));
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if char_length(v_query) < 2 or char_length(v_query) > 80 then
    return jsonb_build_object('items', '[]'::jsonb);
  end if;

  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', result.user_id,
      'name', result.display_name,
      'passport', result.passport,
      'position_id', result.position_id,
      'position', result.position_name,
      'status', result.status
    ) order by result.priority, result.display_name, result.passport), '[]'::jsonb)
  ) into v_result
  from (
    select
      profile.user_id,
      profile.display_name,
      profile.passport,
      profile.position_id,
      position.name as position_name,
      profile.status,
      case when profile.passport = v_query then 0 when profile.passport like v_query || '%' then 1 else 2 end as priority
    from public.profiles profile
    left join public.staff_positions position on position.id = profile.position_id
    where profile.role_code <> 'diretor_geral'
      and profile.status in ('active', 'suspended')
      and (profile.passport like '%' || v_query || '%' or lower(profile.display_name) like '%' || lower(v_query) || '%')
    order by priority, profile.display_name, profile.passport
    limit v_limit
  ) result;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_report_team(p_start_date date, p_end_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  perform private.hpsm_report_validate_period(p_start_date, p_end_date);

  select jsonb_build_object(
    'summary', jsonb_build_object(
      'active_professionals', (select count(*)::integer from public.profiles profile where profile.status = 'active' and profile.role_code <> 'diretor_geral'),
      'admissions', (select count(*)::integer from public.profiles profile where profile.role_code <> 'diretor_geral'
        and profile.created_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
        and profile.created_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')),
      'promotions', (select count(*)::integer from public.staff_position_history history where history.event_type = 'promotion'
        and history.effective_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
        and history.effective_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')),
      'approved_absences', (select count(*)::integer from public.rh_absence_requests absence where absence.status = 'approved'
        and absence.start_date <= p_end_date and absence.end_date >= p_start_date),
      'suspensions', (select count(*)::integer from public.profiles profile where profile.status = 'suspended' and profile.role_code <> 'diretor_geral')
    ),
    'admissions', coalesce((select jsonb_agg(jsonb_build_object(
      'employee_id', admission.user_id,
      'name', admission.display_name,
      'passport', admission.passport,
      'position', admission.position_name,
      'date', admission.admission_date
    ) order by admission.admission_date desc, admission.display_name) from (
      select profile.user_id, profile.display_name, profile.passport, coalesce(position.name, 'Cargo não informado') as position_name,
        (profile.created_at at time zone 'America/Sao_Paulo')::date as admission_date
      from public.profiles profile left join public.staff_positions position on position.id = profile.position_id
      where profile.role_code <> 'diretor_geral'
        and profile.created_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
        and profile.created_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')
      order by profile.created_at desc limit 20
    ) admission), '[]'::jsonb),
    'promotions', coalesce((select jsonb_agg(jsonb_build_object(
      'employee_id', promotion.employee_id,
      'name', promotion.display_name,
      'passport', promotion.passport,
      'from_position', promotion.from_position,
      'to_position', promotion.to_position,
      'date', promotion.promotion_date
    ) order by promotion.promotion_date desc, promotion.display_name) from (
      select history.employee_id, profile.display_name, profile.passport,
        coalesce(previous.name, 'Sem cargo anterior') as from_position,
        current.name as to_position,
        (history.effective_at at time zone 'America/Sao_Paulo')::date as promotion_date
      from public.staff_position_history history
      join public.profiles profile on profile.user_id = history.employee_id
      left join public.staff_positions previous on previous.id = history.from_position_id
      join public.staff_positions current on current.id = history.to_position_id
      where history.event_type = 'promotion'
        and history.effective_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
        and history.effective_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')
      order by history.effective_at desc limit 20
    ) promotion), '[]'::jsonb),
    'absences', coalesce((select jsonb_agg(jsonb_build_object(
      'employee_id', absence.employee_id,
      'name', absence.display_name,
      'passport', absence.passport,
      'position', absence.position_name,
      'start_date', absence.start_date,
      'end_date', absence.end_date,
      'deducted_minutes', absence.deducted_minutes
    ) order by absence.start_date desc, absence.display_name) from (
      select request.employee_id, profile.display_name, profile.passport,
        coalesce(position.name, 'Cargo não informado') as position_name,
        request.start_date, request.end_date,
        coalesce(sum(adjustment.deducted_minutes), 0)::integer as deducted_minutes
      from public.rh_absence_requests request
      join public.profiles profile on profile.user_id = request.employee_id
      left join public.staff_positions position on position.id = profile.position_id
      left join public.rh_leave_week_adjustments adjustment on adjustment.leave_request_id = request.id
      where request.status = 'approved' and request.start_date <= p_end_date and request.end_date >= p_start_date
      group by request.id, request.employee_id, profile.display_name, profile.passport, position.name, request.start_date, request.end_date
      order by request.start_date desc limit 20
    ) absence), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_session_bootstrap()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_auth_actor();
  v_permissions text[];
  v_result jsonb;
begin
  v_permissions := public.effective_permission_codes(v_actor);
  select jsonb_build_object(
    'profile', jsonb_build_object(
      'user_id', profile.user_id,
      'passport', profile.passport,
      'display_name', profile.display_name,
      'role_code', profile.role_code,
      'status', profile.status,
      'must_change_password', profile.must_change_password,
      'position_id', profile.position_id
    ),
    'permissionCodes', to_jsonb(coalesce(v_permissions, array[]::text[])),
    'positionDisplayName', position.name,
    'positionLevel', position.level
  ) into v_result
  from public.profiles profile
  left join public.staff_positions position on position.id = profile.position_id
  where profile.user_id = v_actor and profile.status = 'active';
  if v_result is null then raise exception 'Perfil ativo não localizado.' using errcode = '42501'; end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hpsm_shell_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[] := public.effective_permission_codes(v_actor);
  v_role_code text;
  v_notifications jsonb := '[]'::jsonb;
  v_unread_count integer := 0;
  v_pending_count integer := 0;
  v_weekly_inputs jsonb := null;
  v_today date := timezone('America/Sao_Paulo', now())::date;
  v_week_start date;
  v_cycle_month date;
begin
  select profile.role_code into v_role_code
  from public.profiles profile
  where profile.user_id = v_actor;

  with visible as materialized (
    select
      notification.id,
      notification.kind,
      notification.recipient_id,
      notification.audience,
      notification.priority,
      notification.title,
      notification.body,
      notification.action_url,
      notification.created_by,
      notification.created_at,
      notification.expires_at,
      notification.archived_at,
      notification.source_type,
      notification.source_id,
      notification.required_permission,
      notification.resolved_at,
      notification.resolved_by,
      read.read_at,
      coalesce(author.display_name, 'Sistema HPSM') as author_name,
      author.passport as author_passport
    from public.notifications notification
    left join public.notification_reads read
      on read.notification_id = notification.id and read.user_id = v_actor
    left join public.profiles author on author.user_id = notification.created_by
    where notification.archived_at is null
      and (notification.expires_at is null or notification.expires_at > now())
      and (
        notification.recipient_id = v_actor
        or notification.audience = 'all'
        or (
          notification.audience = 'directors'
          and case
            when notification.required_permission is not null
              then notification.required_permission = any(v_permissions)
            else 'hr.team.view' = any(v_permissions)
          end
        )
        or (
          notification.audience = 'employees'
          and not ('hr.team.view' = any(v_permissions))
        )
      )
  ), picked_ids as (
    (
      select visible.id
      from visible
      where visible.read_at is null and visible.resolved_at is null
      order by visible.created_at desc, visible.id desc
      limit 8
    )
    union
    (
      select visible.id
      from visible
      where visible.kind = 'announcement'
      order by (visible.read_at is null) desc, visible.created_at desc, visible.id desc
      limit 3
    )
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', visible.id,
        'kind', visible.kind,
        'recipient_id', visible.recipient_id,
        'audience', visible.audience,
        'priority', visible.priority,
        'title', visible.title,
        'body', visible.body,
        'action_url', visible.action_url,
        'created_by', visible.created_by,
        'created_at', visible.created_at,
        'expires_at', visible.expires_at,
        'archived_at', visible.archived_at,
        'source_type', visible.source_type,
        'source_id', visible.source_id,
        'required_permission', visible.required_permission,
        'resolved_at', visible.resolved_at,
        'resolved_by', visible.resolved_by,
        'read_at', visible.read_at,
        'author_name', visible.author_name,
        'author_passport', visible.author_passport
      ) order by visible.created_at desc, visible.id desc)
      from visible
      join picked_ids on picked_ids.id = visible.id
    ), '[]'::jsonb),
    (select count(*)::integer from visible where visible.read_at is null and visible.resolved_at is null)
  into v_notifications, v_unread_count;

  select
    (case when 'recruitment.manage' = any(v_permissions)
      then (select count(*) from public.recruitment_applications where status in ('submitted', 'under_review', 'interview')) else 0 end)
    + (case when 'hr.absences.review' = any(v_permissions)
      then (select count(*) from public.rh_absence_requests where status = 'pending') else 0 end)
    + (case when 'hr.justifications.review' = any(v_permissions)
      then (select count(*) from public.rh_hour_justifications where status = 'pending') else 0 end)
    + (case when 'hr.discipline.manage' = any(v_permissions) or 'hr.discipline.review' = any(v_permissions)
      then (select count(*) from public.rh_disciplinary_reviews where status = 'pending') else 0 end)
    + (case when 'progression.review' = any(v_permissions)
      then (select count(*) from public.staff_promotion_reviews where status = 'pending') else 0 end)
    + (case when 'healthplans.review' = any(v_permissions)
      then (select count(*) from public.patient_health_plan_requests where status = 'pending') else 0 end)
    + (case when 'casts.view' = any(v_permissions) and 'casts.manage' = any(v_permissions)
      then (select count(*) from public.clinical_casts where status = 'in_use' and expected_removal_at <= now()) else 0 end)
  into v_pending_count;

  if v_role_code <> 'diretor_geral' then
    v_week_start := v_today - (extract(isodow from v_today)::integer - 1);
    v_cycle_month := date_trunc('month', v_week_start + 6)::date;
    select jsonb_build_object(
      'snapshots', (
        select coalesce(jsonb_agg(to_jsonb(snapshot) order by snapshot.reading_date), '[]'::jsonb)
        from public.rh_hour_snapshots snapshot
        where snapshot.employee_id = v_actor
          and snapshot.reading_date >= date_trunc('month', v_week_start - 1)::date
          and snapshot.reading_date <= v_today
      ),
      'leaveAdjustments', (
        select coalesce(jsonb_agg(to_jsonb(adjustment) order by adjustment.week_start desc), '[]'::jsonb)
        from public.rh_leave_week_adjustments adjustment
        where adjustment.employee_id = v_actor
          and adjustment.week_start = v_week_start
      ),
      'weeklyRecords', (
        select coalesce(jsonb_agg(to_jsonb(record) order by record.week_start desc), '[]'::jsonb)
        from public.rh_weekly_records record
        where record.employee_id = v_actor
          and record.week_start = v_week_start
      ),
      'warnings', (
        select coalesce(jsonb_agg(to_jsonb(warning) order by warning.issued_at desc), '[]'::jsonb)
        from public.rh_warnings warning
        where warning.employee_id = v_actor
          and warning.cycle_month = v_cycle_month
      )
    ) into v_weekly_inputs;
  end if;

  return jsonb_build_object(
    'notifications', v_notifications,
    'unread_count', v_unread_count,
    'pending_count', v_pending_count,
    'weekly_inputs', v_weekly_inputs
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.import_hr_hour_snapshots(p_reading_date date, p_rows jsonb, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_reference_month date := date_trunc('month', p_reading_date)::date;
  v_item jsonb;
  v_passport text;
  v_total integer;
  v_employee public.profiles;
  v_previous integer;
  v_next integer;
  v_seen text[] := array[]::text[];
  v_count integer := 0;
begin
  if not private.has_permission(p_actor_id, 'hr.hours.import') then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode importar horas.';
  end if;
  if p_reading_date is null or p_reading_date > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception using errcode = '22023', message = 'Data da leitura inválida.';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 or jsonb_array_length(p_rows) > 250 then
    raise exception using errcode = '22023', message = 'Nenhuma leitura válida foi informada.';
  end if;

  for v_item in select value from jsonb_array_elements(p_rows)
  loop
    v_passport := btrim(v_item ->> 'passport');
    begin
      v_total := (v_item ->> 'total_minutes')::integer;
    exception when others then
      raise exception using errcode = '22023', message = 'Uma das horas importadas é inválida.';
    end;
    if v_passport is null or v_passport !~ '^[0-9]+$' or v_total not between 0 and 60000 or v_passport = any(v_seen) then
      raise exception using errcode = '22023', message = 'A importação contém passaporte inválido ou repetido.';
    end if;
    v_seen := array_append(v_seen, v_passport);

    select * into v_employee
    from public.profiles
    where passport = v_passport and role_code <> 'diretor_geral' and status <> 'inactive';
    if not found then
      raise exception using errcode = '22023', message = format('Passaporte %s não está disponível para importação.', v_passport);
    end if;

    select total_minutes into v_previous
    from public.rh_hour_snapshots
    where employee_id = v_employee.user_id
      and reference_month = v_reference_month
      and reading_date < p_reading_date
    order by reading_date desc limit 1;
    select total_minutes into v_next
    from public.rh_hour_snapshots
    where employee_id = v_employee.user_id
      and reference_month = v_reference_month
      and reading_date > p_reading_date
    order by reading_date asc limit 1;

    if v_previous is not null and v_total < v_previous then
      raise exception using errcode = '22023', message = format('O acumulado do passaporte %s é menor que a leitura anterior deste mês.', v_passport);
    end if;
    if v_next is not null and v_total > v_next then
      raise exception using errcode = '22023', message = format('O acumulado do passaporte %s ultrapassa uma leitura posterior.', v_passport);
    end if;

    insert into public.rh_hour_snapshots (
      employee_id, reference_month, reading_date, total_minutes, note, created_by, updated_by
    ) values (
      v_employee.user_id, v_reference_month, p_reading_date, v_total,
      'Importação em lote da Diretoria.', p_actor_id, p_actor_id
    )
    on conflict (employee_id, reference_month, reading_date) do update
    set total_minutes = excluded.total_minutes,
        note = excluded.note,
        updated_by = p_actor_id,
        updated_at = now();
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('saved', v_count, 'reading_date', p_reading_date, 'reference_month', v_reference_month);
end;
$function$;

CREATE OR REPLACE FUNCTION public.import_partnership_people(p_partnership_id bigint, p_people jsonb, p_source text DEFAULT 'batch'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
begin
  return private.partnership_apply_people(p_partnership_id, p_people, 'professional', v_actor, null, p_source);
end;
$function$;

CREATE OR REPLACE FUNCTION public.issue_hr_warning(p_employee_id uuid, p_weekly_record_id bigint, p_cycle_month date, p_category text, p_reason text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles;
  v_week public.rh_weekly_records;
  v_cycle date;
  v_origin text;
  v_count integer;
  v_warning public.rh_warnings;
  v_suspended boolean := false;
begin
  if not private.has_permission(p_actor_id, 'hr.warnings.issue') then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode aplicar advertências.';
  end if;
  if p_employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode aplicar advertência a si próprio.';
  end if;
  if p_category not in ('weekly_goal', 'attendance', 'conduct', 'internal_rules', 'other') then
    raise exception using errcode = '22023', message = 'Categoria de advertência inválida.';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 1000 then
    raise exception using errcode = '22023', message = 'Informe a ocorrência entre 10 e 1000 caracteres.';
  end if;

  select * into v_profile from public.profiles where user_id = p_employee_id for update;
  if not found or v_profile.role_code = 'diretor_geral' or v_profile.status = 'inactive' then
    raise exception using errcode = '22023', message = 'Colaborador indisponível para advertência.';
  end if;

  if p_weekly_record_id is not null then
    select * into v_week
    from public.rh_weekly_records
    where id = p_weekly_record_id
    for update;
    if not found or v_week.employee_id <> p_employee_id or v_week.closure_status <> 'closed'
       or v_week.remaining_deficit_minutes <= 0 then
      raise exception using errcode = '22023', message = 'O fechamento não possui déficit elegível para advertência.';
    end if;
    if exists (select 1 from public.rh_warnings where weekly_record_id = v_week.id) then
      raise exception using errcode = '23505', message = 'Já existe advertência vinculada a esta semana.';
    end if;
    v_cycle := v_week.cycle_month;
    v_origin := 'weekly_closure';
  else
    if p_cycle_month is null or p_cycle_month <> date_trunc('month', p_cycle_month)::date then
      raise exception using errcode = '22023', message = 'Competência mensal inválida.';
    end if;
    v_cycle := p_cycle_month;
    v_origin := 'manual';
  end if;

  select count(*)::integer into v_count
  from public.rh_warnings
  where employee_id = p_employee_id and cycle_month = v_cycle and status = 'active';
  if v_count >= 3 then
    raise exception using errcode = 'P0001', message = 'O colaborador já possui três advertências ativas neste ciclo.';
  end if;
  v_count := v_count + 1;

  insert into public.rh_warnings (
    employee_id, weekly_record_id, cycle_month, sequence_in_cycle,
    reason, issued_by, origin, category
  ) values (
    p_employee_id, p_weekly_record_id, v_cycle, v_count,
    btrim(p_reason), p_actor_id, v_origin, p_category
  ) returning * into v_warning;

  if p_weekly_record_id is not null then
    update public.rh_weekly_records
    set status = 'warning_issued', updated_at = now()
    where id = p_weekly_record_id;
  end if;

  if v_count = 3 then
    update public.profiles
    set status = 'suspended', updated_by = p_actor_id, updated_at = now()
    where user_id = p_employee_id;

    insert into public.rh_disciplinary_reviews (
      employee_id, cycle_month, triggered_by_warning_id, triggered_by
    ) values (
      p_employee_id, v_cycle, v_warning.id, p_actor_id
    );
    v_suspended := true;
  end if;

  return jsonb_build_object(
    'warning', to_jsonb(v_warning),
    'active_warnings', v_count,
    'suspended', v_suspended
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.manage_exam_category(p_id bigint, p_name text, p_code text, p_active boolean, p_sort_order integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_old public.exam_categories;
  v_new public.exam_categories;
  v_action text;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.catalog.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_id is null then
    insert into public.exam_categories (code, name, active, sort_order, created_by, updated_by)
    values (btrim(p_code), btrim(p_name), coalesce(p_active, true), p_sort_order, v_actor, v_actor)
    returning * into v_new;
    v_action := 'exam_category.created';
  else
    select * into v_old from public.exam_categories where id = p_id for update;
    if v_old.id is null then raise exception 'Categoria não localizada.'; end if;
    update public.exam_categories set
      name = btrim(p_name), active = p_active, sort_order = p_sort_order, updated_by = v_actor
    where id = p_id returning * into v_new;
    v_action := case when v_old.active is distinct from v_new.active then 'exam_category.status_changed' else 'exam_category.updated' end;
  end if;
  perform private.audit_exam_action(v_actor, v_action, 'exam_categories', v_new.id::text, case when v_old.id is null then null else to_jsonb(v_old) end, to_jsonb(v_new));
  return v_new.id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.manage_exam_imaging_template(p_exam_type_id bigint, p_expected_version integer, p_region_required boolean, p_region_options jsonb, p_supports_laterality boolean, p_supports_contrast boolean, p_requires_image boolean, p_allows_multiple_images boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_type public.exam_types;
  v_old_config jsonb;
  v_new_config jsonb;
  v_new_version integer;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.catalog.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select exam_type.* into v_type
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = p_exam_type_id and category.code = 'imagem'
  for update of exam_type;
  if v_type.id is null or v_type.result_config->>'kind' <> 'imaging' then
    raise exception 'Template de imagem não localizado.';
  end if;
  if p_expected_version is distinct from (v_type.result_config->>'version')::integer then
    raise exception 'O template foi atualizado por outra pessoa. Reabra-o antes de salvar.';
  end if;
  if jsonb_typeof(p_region_options) <> 'array' then raise exception 'A lista de regiões é inválida.'; end if;

  v_old_config := v_type.result_config;
  v_new_version := p_expected_version + 1;
  v_new_config := jsonb_build_object(
    'schema', 'hpsm.image_template.v1',
    'kind', 'imaging',
    'version', v_new_version,
    'region', jsonb_build_object('required', coalesce(p_region_required, true), 'options', p_region_options),
    'supports_laterality', coalesce(p_supports_laterality, false),
    'supports_contrast', coalesce(p_supports_contrast, false),
    'requires_image', coalesce(p_requires_image, true),
    'allows_multiple_images', coalesce(p_allows_multiple_images, true)
  );
  perform private.assert_valid_image_template(v_new_config);

  update public.exam_types set result_config = v_new_config, updated_by = v_actor
  where id = p_exam_type_id;
  perform private.audit_exam_action(
    v_actor, 'exam_imaging_template.updated', 'exam_types', p_exam_type_id::text,
    jsonb_build_object('result_config', v_old_config), jsonb_build_object('result_config', v_new_config)
  );
  return v_new_version;
end;
$function$;

CREATE OR REPLACE FUNCTION public.manage_exam_template(p_exam_type_id bigint, p_expected_version integer, p_parameters jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_type public.exam_types;
  v_old_config jsonb;
  v_new_config jsonb;
  v_new_version integer;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.catalog.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select exam_type.* into v_type
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = p_exam_type_id and category.code = 'laboratorial'
  for update of exam_type;
  if v_type.id is null or v_type.result_config->>'kind' <> 'laboratory' then
    raise exception 'Template laboratorial não localizado.';
  end if;
  if p_expected_version is distinct from (v_type.result_config->>'version')::integer then
    raise exception 'O template foi atualizado por outra pessoa. Reabra-o antes de salvar.';
  end if;
  if jsonb_typeof(p_parameters) <> 'array' then
    raise exception 'A lista de parâmetros é inválida.';
  end if;

  v_old_config := v_type.result_config;
  v_new_version := p_expected_version + 1;
  v_new_config := jsonb_build_object(
    'schema', 'hpsm.lab_template.v1',
    'kind', 'laboratory',
    'version', v_new_version,
    'parameters', p_parameters
  );
  perform private.assert_valid_lab_template(v_new_config);

  if exists (
    select 1
    from jsonb_array_elements(v_old_config->'parameters') old_parameter
    where not exists (
      select 1 from jsonb_array_elements(p_parameters) new_parameter
      where new_parameter->>'key' = old_parameter->>'key'
    )
    and exists (
      select 1
      from public.clinical_exams exam
      cross join lateral jsonb_array_elements(coalesce(exam.result_data#>'{template_snapshot,parameters}', '[]'::jsonb)) historical_parameter
      where exam.exam_type_id = p_exam_type_id
        and historical_parameter->>'key' = old_parameter->>'key'
    )
  ) then
    raise exception 'Parâmetros já usados em exames devem ser inativados, não removidos.';
  end if;

  update public.exam_types
  set result_config = v_new_config, updated_by = v_actor
  where id = p_exam_type_id;

  perform private.audit_exam_action(
    v_actor,
    'exam_template.updated',
    'exam_types',
    p_exam_type_id::text,
    jsonb_build_object('result_config', v_old_config),
    jsonb_build_object('result_config', v_new_config)
  );
  return v_new_version;
end;
$function$;

CREATE OR REPLACE FUNCTION public.manage_exam_type(p_id bigint, p_category_id bigint, p_name text, p_code text, p_description text, p_active boolean, p_sort_order integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_old public.exam_types;
  v_new public.exam_types;
  v_category_active boolean;
  v_category_code text;
  v_result_config jsonb := '{}'::jsonb;
  v_action text;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.catalog.manage') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select category.active, category.code into v_category_active, v_category_code from public.exam_categories category where category.id = p_category_id;
  if v_category_active is null then raise exception 'Categoria não localizada.'; end if;
  if p_active and not v_category_active then raise exception 'Ative a categoria antes de ativar o tipo de exame.'; end if;
  if v_category_code = 'laboratorial' then
    v_result_config := jsonb_build_object('schema','hpsm.lab_template.v1','kind','laboratory','version',1,'parameters',jsonb_build_array());
  elsif v_category_code = 'imagem' then
    v_result_config := private.default_image_template(btrim(p_code));
  end if;
  if p_id is null then
    insert into public.exam_types (category_id, code, name, description, active, sort_order, result_config, created_by, updated_by)
    values (p_category_id, btrim(p_code), btrim(p_name), nullif(btrim(p_description), ''), coalesce(p_active, true), p_sort_order, v_result_config, v_actor, v_actor)
    returning * into v_new;
    v_action := 'exam_type.created';
  else
    select * into v_old from public.exam_types where id = p_id for update;
    if v_old.id is null then raise exception 'Tipo de exame não localizado.'; end if;
    update public.exam_types set
      category_id = p_category_id,
      name = btrim(p_name),
      description = nullif(btrim(p_description), ''),
      active = p_active,
      sort_order = p_sort_order,
      result_config = case
        when v_category_code = 'laboratorial' and result_config->>'kind' is distinct from 'laboratory' then v_result_config
        when v_category_code = 'imagem' and result_config->>'kind' is distinct from 'imaging' then v_result_config
        else result_config
      end,
      updated_by = v_actor
    where id = p_id returning * into v_new;
    v_action := case when v_old.active is distinct from v_new.active then 'exam_type.status_changed' else 'exam_type.updated' end;
  end if;
  perform private.audit_exam_action(v_actor, v_action, 'exam_types', v_new.id::text, case when v_old.id is null then null else to_jsonb(v_old) end, to_jsonb(v_new));
  return v_new.id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read(p_actor_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_count integer;
begin
  if not exists (
    select 1 from public.profiles
    where user_id = p_actor_id and status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'Usuario sem acesso ativo.';
  end if;

  insert into public.notification_reads (notification_id, user_id)
  select n.id, p_actor_id
  from public.notifications n
  where private.can_view_notification(n.id, p_actor_id)
  on conflict (notification_id, user_id) do update
  set read_at = excluded.read_at;

  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id bigint, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row public.notification_reads;
begin
  if not private.can_view_notification(p_notification_id, p_actor_id) then
    raise exception using errcode = '42501', message = 'Notificacao indisponivel para este usuario.';
  end if;

  insert into public.notification_reads (notification_id, user_id)
  values (p_notification_id, p_actor_id)
  on conflict (notification_id, user_id) do update
  set read_at = excluded.read_at
  returning * into v_row;

  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.override_staff_position(p_employee_id uuid, p_to_position_id bigint, p_note text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor public.profiles;
  v_actor_position public.staff_positions;
  v_employee public.profiles;
  v_from public.staff_positions;
  v_to public.staff_positions;
  v_history public.staff_position_history;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  select * into v_actor from public.profiles where user_id = p_actor_id;
  select * into v_actor_position from public.staff_positions where id = v_actor.position_id;
  if not found
     or v_actor.role_code <> 'diretor_geral'
     or v_actor.status <> 'active'
     or v_actor_position.level <> 14 then
    raise exception using errcode = '42501', message = 'Somente o Diretor Geral pode alterar cargos diretamente.';
  end if;
  if p_employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'O cargo de Diretor Geral só pode ser alterado pelo fluxo de sucessão.';
  end if;
  if v_note is not null and char_length(v_note) not between 2 and 2000 then
    raise exception using errcode = '22023', message = 'A observação deve possuir entre 2 e 2000 caracteres.';
  end if;

  select * into v_employee from public.profiles where user_id = p_employee_id for update;
  if not found or v_employee.status = 'inactive' or v_employee.role_code = 'diretor_geral' then
    raise exception using errcode = '22023', message = 'Colaborador indisponível para alteração direta de cargo.';
  end if;
  select * into v_from from public.staff_positions where id = v_employee.position_id;
  select * into v_to from public.staff_positions where id = p_to_position_id and active;
  if not found or v_to.level = 14 then
    raise exception using errcode = '22023', message = 'O cargo de Diretor Geral exige o fluxo de sucessão.';
  end if;
  if v_employee.position_id = v_to.id then
    raise exception using errcode = '22023', message = 'Selecione um cargo diferente do atual.';
  end if;

  perform set_config('hpsm.position_change_authorized', 'true', true);
  update public.profiles
  set position_id = v_to.id, updated_by = p_actor_id, updated_at = now()
  where user_id = p_employee_id and position_id is not distinct from v_employee.position_id;
  if not found then
    raise exception using errcode = '40001', message = 'O cargo foi alterado durante a operação. Atualize a página.';
  end if;

  update public.staff_promotion_reviews
  set status = 'cancelled', decided_by = p_actor_id, decided_at = now(),
      decision_note = 'Encerrada por alteração direta de cargo pelo Diretor Geral.', updated_at = now()
  where employee_id = p_employee_id and status in ('pending', 'deferred');

  insert into public.staff_position_history (
    employee_id, from_position_id, to_position_id, event_type, decided_by, note
  ) values (
    p_employee_id, v_employee.position_id, v_to.id, 'override', p_actor_id, v_note
  ) returning * into v_history;

  insert into public.notifications (
    kind, recipient_id, priority, title, body, action_url, created_by
  ) values (
    'personal', p_employee_id, 'important', 'Cargo alterado pela Direção Geral',
    format('Seu cargo foi alterado para %s. Consulte o histórico no Meu RH.', v_to.name),
    '/meu-rh', p_actor_id
  );

  return to_jsonb(v_history);
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_active_clinical_casts(p_patient_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, 'patients.view')
     or not private.has_permission(v_actor, 'casts.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', cast_record.id,
      'patient_id', cast_record.patient_id,
      'body_region', cast_record.body_region,
      'laterality', cast_record.laterality,
      'status', cast_record.status,
      'applied_at', cast_record.applied_at,
      'expected_removal_at', cast_record.expected_removal_at,
      'applied_by', cast_record.applied_by,
      'applied_by_name', applied.display_name,
      'applied_by_position', applied_position.name
    ) order by cast_record.expected_removal_at, cast_record.id)
    from public.clinical_casts cast_record
    join public.profiles applied on applied.user_id = cast_record.applied_by
    left join public.staff_positions applied_position on applied_position.id = applied.position_id
    where cast_record.patient_id = p_patient_id
      and cast_record.status = 'in_use'
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_activity_page(p_patient_id bigint, p_kind text DEFAULT 'all'::text, p_month date DEFAULT NULL::date, p_limit integer DEFAULT 10, p_offset integer DEFAULT 0)
 RETURNS TABLE(total_count bigint, records jsonb, selected_month text, available_months jsonb, monthly_total numeric, monthly_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_selected_month date;
  v_months jsonb;
begin
  if not private.has_permission((select auth.uid()), 'patients.view') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para consultar pacientes.';
  end if;
  if p_kind not in ('all', 'purchases', 'procedures') then
    raise exception using errcode = '22023', message = 'Tipo de histórico inválido.';
  end if;
  if p_limit < 1 or p_limit > 50 or p_offset < 0 then
    raise exception using errcode = '22023', message = 'Paginação inválida.';
  end if;
  if p_month is not null and p_month <> date_trunc('month', p_month)::date then
    raise exception using errcode = '22023', message = 'Competência mensal inválida.';
  end if;

  select coalesce(
    p_month,
    max(date_trunc('month', attendance.created_at at time zone 'America/Sao_Paulo')::date),
    date_trunc('month', now() at time zone 'America/Sao_Paulo')::date
  ) into v_selected_month
  from public.attendances attendance
  where attendance.patient_id = p_patient_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'month', month_row.month_code,
    'count', month_row.record_count,
    'total', month_row.total_value
  ) order by month_row.month_code desc), '[]'::jsonb)
  into v_months
  from (
    select
      to_char(date_trunc('month', attendance.created_at at time zone 'America/Sao_Paulo'), 'YYYY-MM') as month_code,
      count(*) filter (where attendance.status = 'completed')::bigint as record_count,
      coalesce(sum(attendance.total) filter (where attendance.status = 'completed'), 0)::numeric as total_value
    from public.attendances attendance
    where attendance.patient_id = p_patient_id
    group by date_trunc('month', attendance.created_at at time zone 'America/Sao_Paulo')
  ) month_row;

  return query
  with matching as materialized (
    select attendance.*
    from public.attendances attendance
    where attendance.patient_id = p_patient_id
      and attendance.created_at >= (v_selected_month::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < ((v_selected_month + interval '1 month')::timestamp at time zone 'America/Sao_Paulo')
      and (
        p_kind = 'all'
        or exists (
          select 1
          from public.attendance_items item
          join public.service_catalog service on service.id = item.service_id
          where item.attendance_id = attendance.id
            and (
              (p_kind = 'purchases' and lower(service.category) in ('insumos', 'medicamentos', 'produtos', 'convênios'))
              or (p_kind = 'procedures' and lower(service.category) in ('atendimentos', 'exames'))
            )
        )
      )
  ), page as (
    select matching.*
    from matching
    order by matching.created_at desc, matching.id desc
    limit p_limit offset p_offset
  ), rendered as (
    select
      page.created_at,
      page.id,
      jsonb_build_object(
        'id', page.id,
        'created_at', page.created_at,
        'status', page.status,
        'patient_name', page.patient_name,
        'patient_passport', page.patient_passport,
        'plan_code', page.plan_code,
        'plan_name', page.plan_name,
        'subtotal', page.subtotal,
        'discount', page.discount,
        'total', page.total,
        'notes', page.notes,
        'professional_name', coalesce(professional.display_name, 'Profissional'),
        'professional_passport', coalesce(professional.passport, '—'),
        'professional_position', coalesce(position.name, 'Cargo não definido'),
        'items', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', item.id,
            'service_id', item.service_id,
            'service_name', item.service_name,
            'category', service.category,
            'code', service.code,
            'unit_price', item.unit_price,
            'quantity', item.quantity,
            'discount_percent', item.discount_percent,
            'discount_amount', item.discount_amount,
            'line_total', item.line_total
          ) order by item.id)
          from public.attendance_items item
          join public.service_catalog service on service.id = item.service_id
          where item.attendance_id = page.id
            and (
              p_kind = 'all'
              or (p_kind = 'purchases' and lower(service.category) in ('insumos', 'medicamentos', 'produtos', 'convênios'))
              or (p_kind = 'procedures' and lower(service.category) in ('atendimentos', 'exames'))
            )
        ), '[]'::jsonb)
      ) as record
    from page
    left join public.profiles professional on professional.user_id = page.performed_by
    left join public.staff_positions position on position.id = professional.position_id
  )
  select
    (select count(*) from matching)::bigint,
    coalesce(jsonb_agg(rendered.record order by rendered.created_at desc, rendered.id desc), '[]'::jsonb),
    to_char(v_selected_month, 'YYYY-MM'),
    v_months,
    coalesce((select sum(matching.total) from matching where matching.status = 'completed'), 0)::numeric,
    (select count(*) from matching where matching.status = 'completed')::bigint
  from rendered;
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_clinical_exam_page(p_patient_id bigint, p_category_id bigint DEFAULT NULL::bigint, p_exam_type_id bigint DEFAULT NULL::bigint, p_status text DEFAULT NULL::text, p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_limit integer DEFAULT 10, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 10), 1), 20);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if v_actor is null
     or not private.has_permission(v_actor, 'patients.view')
     or not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_patient_id is null or not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;
  if p_status is not null and p_status not in ('requested', 'in_progress', 'awaiting_review', 'completed') then
    raise exception 'Status inválido.';
  end if;

  with base as materialized (
    select
      exam.id,
      exam.patient_id,
      exam.exam_type_id,
      exam_type.name as exam_type_name,
      category.id as category_id,
      category.name as category_name,
      exam.status,
      exam.indication,
      exam.responsible_professional_id,
      responsible.display_name as responsible_name,
      responsible_position.name as responsible_position,
      reviewer.display_name as reviewer_name,
      reviewer_position.name as reviewer_position,
      exam.requested_at,
      exam.completed_at,
      coalesce(exam.completed_at, exam.requested_at) as relevant_at
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    join public.exam_categories category on category.id = exam_type.category_id
    join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
    left join public.staff_positions responsible_position on responsible_position.id = responsible.position_id
    left join public.profiles reviewer on reviewer.user_id = exam.reviewed_by
    left join public.staff_positions reviewer_position on reviewer_position.id = reviewer.position_id
    where exam.patient_id = p_patient_id
  ), filtered as materialized (
    select *
    from base
    where (p_category_id is null or category_id = p_category_id)
      and (p_exam_type_id is null or exam_type_id = p_exam_type_id)
      and (p_status is null or status = p_status)
      and (p_date_from is null or relevant_at >= p_date_from::timestamptz)
      and (p_date_to is null or relevant_at < (p_date_to + 1)::timestamptz)
  ), page_rows as materialized (
    select * from filtered order by relevant_at desc, id desc limit v_limit offset v_offset
  ), image_counts as (
    select image.exam_id, count(*)::integer as image_count
    from public.clinical_exam_images image
    where image.removed_at is null
      and image.exam_id in (select page_row.id from page_rows page_row)
    group by image.exam_id
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(
        to_jsonb(page_row) || jsonb_build_object('image_count', coalesce(image_count.image_count, 0))
        order by page_row.relevant_at desc, page_row.id desc
      )
      from page_rows page_row
      left join image_counts image_count on image_count.exam_id = page_row.id
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'summary', jsonb_build_object(
      'total', (select count(*) from base),
      'completed', (select count(*) from base where status = 'completed'),
      'awaiting_review', (select count(*) from base where status = 'awaiting_review')
    )
  ) into v_result;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_partnership_page(p_patient_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.partnership_assert_professional('patients.view');
  v_result jsonb;
begin
  if not exists (select 1 from public.patients where id = p_patient_id) then
    raise exception 'Paciente não localizado.' using errcode = '22023';
  end if;
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', partnership.id,
      'name', partnership.name,
      'status', partnership.status,
      'linked_at', membership.linked_at
    ) order by (partnership.status = 'active') desc, lower(partnership.name)), '[]'::jsonb)
  ) into v_result
  from public.patient_partnerships membership
  join public.partnerships partnership on partnership.id = membership.partnership_id
  where membership.patient_id = p_patient_id and membership.status = 'active';
  return v_result;
end;
$function$;


CREATE OR REPLACE FUNCTION public.patient_portal_attendance_detail(p_token_hash text, p_attendance_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_items jsonb;
  v_session record;
  v_target record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select *
  into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select
    attendance.id,
    attendance.created_at,
    attendance.plan_code,
    attendance.plan_name,
    attendance.subtotal,
    attendance.discount,
    attendance.total,
    professional.display_name as professional_name,
    position.name as professional_position
  into v_target
  from public.attendances attendance
  left join public.profiles professional on professional.user_id = attendance.performed_by
  left join public.staff_positions position on position.id = professional.position_id
  where attendance.id = p_attendance_id
    and attendance.patient_id = v_session.patient_id
    and attendance.status = 'completed';

  if not found then
    return jsonb_build_object('authenticated', true, 'found', false);
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name', item.service_name,
        'unit_price', item.unit_price,
        'quantity', item.quantity,
        'discount_percent', item.discount_percent,
        'discount_amount', item.discount_amount,
        'line_total', item.line_total
      ) order by item.id
    ),
    '[]'::jsonb
  )
  into v_items
  from public.attendance_items item
  where item.attendance_id = v_target.id;

  return jsonb_build_object(
    'authenticated', true,
    'found', true,
    'patient', jsonb_build_object(
      'name', v_session.patient_name,
      'passport', v_session.patient_passport
    ),
    'attendance', jsonb_build_object(
      'id', v_target.id,
      'occurred_at', v_target.created_at,
      'professional_name', v_target.professional_name,
      'professional_position', v_target.professional_position,
      'benefit_code', v_target.plan_code,
      'benefit_name', v_target.plan_name,
      'subtotal', v_target.subtotal,
      'discount', v_target.discount,
      'total', v_target.total,
      'items', v_items
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_attendance_page(p_token_hash text, p_cursor_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id bigint DEFAULT NULL::bigint, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_has_more boolean;
  v_items jsonb;
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_metrics record;
  v_next_at timestamptz;
  v_next_id bigint;
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;
  if (p_cursor_at is null) <> (p_cursor_id is null) or p_cursor_id is not null and p_cursor_id < 1 then
    raise exception 'Cursor inválido.' using errcode = '22023';
  end if;

  select *
  into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select *
  into v_metrics
  from private.patient_portal_attendance_metrics(v_session.patient_id);

  with page_rows as materialized (
    select
      attendance.id,
      attendance.created_at,
      attendance.plan_code,
      attendance.plan_name,
      attendance.total,
      professional.display_name as professional_name,
      position.name as professional_position
    from public.attendances attendance
    left join public.profiles professional on professional.user_id = attendance.performed_by
    left join public.staff_positions position on position.id = professional.position_id
    where attendance.patient_id = v_session.patient_id
      and attendance.status = 'completed'
      and (
        p_cursor_at is null
        or (attendance.created_at, attendance.id) < (p_cursor_at, p_cursor_id)
      )
    order by attendance.created_at desc, attendance.id desc
    limit v_limit + 1
  ), visible_rows as materialized (
    select * from page_rows order by created_at desc, id desc limit v_limit
  ), item_counts as (
    select item.attendance_id, sum(item.quantity)::integer as item_count
    from public.attendance_items item
    join visible_rows visible on visible.id = item.attendance_id
    group by item.attendance_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', visible.id,
          'occurred_at', visible.created_at,
          'professional_name', visible.professional_name,
          'professional_position', visible.professional_position,
          'item_count', coalesce(item_counts.item_count, 0),
          'benefit_code', visible.plan_code,
          'benefit_name', visible.plan_name,
          'total', visible.total
        ) order by visible.created_at desc, visible.id desc
      ),
      '[]'::jsonb
    ),
    (select count(*) > v_limit from page_rows),
    (select created_at from visible_rows order by created_at, id limit 1),
    (select id from visible_rows order by created_at, id limit 1)
  into v_items, v_has_more, v_next_at, v_next_id
  from visible_rows visible
  left join item_counts on item_counts.attendance_id = visible.id;

  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object(
      'name', v_session.patient_name,
      'passport', v_session.patient_passport
    ),
    'summary', jsonb_build_object(
      'total_attendances', v_metrics.total_attendances,
      'lifetime_spent', v_metrics.lifetime_spent
    ),
    'items', v_items,
    'next_cursor', case
      when v_has_more then jsonb_build_object('occurred_at', v_next_at, 'id', v_next_id)
      else null
    end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_cancel_partnership_pending(p_token_hash text, p_partnership_id bigint, p_record_key text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_patient_id bigint := private.partnership_portal_actor(p_token_hash, p_partnership_id, true);
  v_pending public.partnership_pending_beneficiaries%rowtype;
  v_id bigint;
begin
  if p_record_key !~ '^p:[0-9]+$' then raise exception 'Pré-beneficiário inválido.' using errcode = '22023'; end if;
  v_id := substring(p_record_key from 3)::bigint;
  select * into v_pending from public.partnership_pending_beneficiaries
  where id = v_id and partnership_id = p_partnership_id for update;
  if not found or v_pending.status not in ('pending_registration', 'name_review') then
    raise exception 'Pré-beneficiário pendente não localizado.' using errcode = '22023';
  end if;
  update public.partnership_pending_beneficiaries set status = 'canceled', canceled_at = now(),
    canceled_by_type = 'partnership_responsible', canceled_by_patient_id = v_actor_patient_id,
    cancellation_reason = 'Cancelado pelo responsável da parceria.'
  where id = v_id;
  perform private.partnership_audit('PARTNERSHIP_PENDING_CANCELED', 'partnership_pending_beneficiaries', v_id::text,
    'partnership_responsible', null, v_actor_patient_id, null,
    jsonb_build_object('partnership_id', p_partnership_id, 'passport', v_pending.passport));
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_cast_page(p_token_hash text, p_cursor_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id bigint DEFAULT NULL::bigint, p_limit integer DEFAULT 15)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_active jsonb;
  v_has_more boolean;
  v_history jsonb;
  v_limit integer := least(greatest(coalesce(p_limit, 15), 1), 30);
  v_next_at timestamptz;
  v_next_id bigint;
  v_reference_time timestamptz := clock_timestamp();
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;
  if (p_cursor_at is null) <> (p_cursor_id is null)
     or (p_cursor_id is not null and p_cursor_id < 1) then
    raise exception 'Cursor inválido.' using errcode = '22023';
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'key', 'cast:' || active.id::text,
    'body_region', active.body_region,
    'laterality', active.laterality,
    'status', active.status,
    'applied_at', active.applied_at,
    'expected_removal_at', active.expected_removal_at,
    'applied_by_name', active.applied_by_name,
    'applied_by_position', active.applied_by_position
  ) order by active.expected_removal_at, active.id), '[]'::jsonb)
  into v_active
  from (
    select
      cast_record.id,
      cast_record.body_region,
      cast_record.laterality,
      cast_record.status,
      cast_record.applied_at,
      cast_record.expected_removal_at,
      applied.display_name as applied_by_name,
      applied_position.name as applied_by_position
    from public.clinical_casts cast_record
    left join public.profiles applied on applied.user_id = cast_record.applied_by
    left join public.staff_positions applied_position on applied_position.id = applied.position_id
    where cast_record.patient_id = v_session.patient_id
      and cast_record.status = 'in_use'
    order by cast_record.expected_removal_at, cast_record.id
  ) active;

  with page_rows as materialized (
    select
      cast_record.id,
      cast_record.updated_at as event_at,
      cast_record.body_region,
      cast_record.laterality,
      cast_record.status,
      cast_record.applied_at,
      cast_record.expected_removal_at,
      cast_record.removed_at,
      cast_record.cancelled_at,
      applied.display_name as applied_by_name,
      applied_position.name as applied_by_position,
      removed.display_name as removed_by_name,
      removed_position.name as removed_by_position
    from public.clinical_casts cast_record
    left join public.profiles applied on applied.user_id = cast_record.applied_by
    left join public.staff_positions applied_position on applied_position.id = applied.position_id
    left join public.profiles removed on removed.user_id = cast_record.removed_by
    left join public.staff_positions removed_position on removed_position.id = removed.position_id
    where cast_record.patient_id = v_session.patient_id
      and cast_record.status in ('removed', 'cancelled')
      and (
        p_cursor_at is null
        or (cast_record.updated_at, cast_record.id) < (p_cursor_at, p_cursor_id)
      )
    order by cast_record.updated_at desc, cast_record.id desc
    limit v_limit + 1
  ), visible_rows as materialized (
    select *
    from page_rows
    order by event_at desc, id desc
    limit v_limit
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'key', 'cast:' || visible.id::text,
      'body_region', visible.body_region,
      'laterality', visible.laterality,
      'status', visible.status,
      'occurred_at', visible.event_at,
      'applied_at', visible.applied_at,
      'expected_removal_at', visible.expected_removal_at,
      'removed_at', visible.removed_at,
      'cancelled_at', visible.cancelled_at,
      'applied_by_name', visible.applied_by_name,
      'applied_by_position', visible.applied_by_position,
      'removed_by_name', visible.removed_by_name,
      'removed_by_position', visible.removed_by_position
    ) order by visible.event_at desc, visible.id desc), '[]'::jsonb),
    (select count(*) > v_limit from page_rows),
    (select event_at from visible_rows order by event_at, id limit 1),
    (select id from visible_rows order by event_at, id limit 1)
  into v_history, v_has_more, v_next_at, v_next_id
  from visible_rows visible;

  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object(
      'name', v_session.patient_name,
      'passport', v_session.patient_passport
    ),
    'reference_time', v_reference_time,
    'active_casts', v_active,
    'history', v_history,
    'next_cursor', case
      when v_has_more then jsonb_build_object('occurred_at', v_next_at, 'id', v_next_id)
      else null
    end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_create_clinical_exam_document_share(p_token_hash text, p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_document public.clinical_exam_documents;
  v_session record;
  v_share public.clinical_exam_document_shares;
  v_target public.clinical_exams;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select exam.* into v_target
  from public.clinical_exams exam
  where exam.id = p_exam_id and exam.patient_id = v_session.patient_id
  for update;

  if not found or v_target.status <> 'completed' or v_target.final_report_snapshot is null then
    return jsonb_build_object('authenticated', true, 'found', false);
  end if;

  select document.* into v_document
  from public.clinical_exam_documents document
  where document.exam_id = p_exam_id and document.render_version = 'exam-document-png-v4'
  limit 1;

  if v_document.id is null then
    raise exception 'Prepare a imagem do resultado antes de criar o link.';
  end if;

  insert into public.clinical_exam_document_shares (
    exam_id, document_id, created_by, created_by_patient_id
  ) values (
    p_exam_id, v_document.id, null, v_session.patient_id
  ) on conflict (exam_id) where revoked_at is null do nothing;

  select share.* into v_share
  from public.clinical_exam_document_shares share
  where share.exam_id = p_exam_id and share.revoked_at is null
  limit 1;

  if v_share.id is null then
    raise exception 'Não foi possível criar o link do resultado.';
  end if;

  return jsonb_build_object(
    'authenticated', true,
    'found', true,
    'state', private.clinical_exam_document_state_json(p_exam_id)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_create_session(p_passport text, p_birth_date date, p_token_hash text, p_origin_hash text, p_client_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_block_scope text;
  v_expires_at timestamptz;
  v_origin_failures integer;
  v_passport text := btrim(coalesce(p_passport, ''));
  v_passport_failures integer;
  v_passport_hash text;
  v_patient public.patients%rowtype;
begin
  if v_passport !~ '^[0-9]{1,4}$'
     or p_birth_date is null
     or p_birth_date > current_date
     or p_token_hash is null
     or p_token_hash !~ '^[0-9a-f]{64}$'
     or p_origin_hash is null
     or p_origin_hash !~ '^[0-9a-f]{64}$'
     or (p_client_hash is not null and p_client_hash !~ '^[0-9a-f]{64}$') then
    return jsonb_build_object('ok', false, 'blocked', false);
  end if;

  v_passport_hash := encode(
    extensions.digest('patient-portal:' || v_passport, 'sha256'),
    'hex'
  );

  -- Serializa tentativas do mesmo passaporte antes de contar e gravar.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_passport_hash, 0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_origin_hash, 1));

  select count(*)::integer
  into v_passport_failures
  from public.patient_portal_login_attempts attempt
  where attempt.passport_hash = v_passport_hash
    and not attempt.succeeded
    and not attempt.blocked
    and attempt.attempted_at >= clock_timestamp() - interval '15 minutes';

  select count(*)::integer
  into v_origin_failures
  from public.patient_portal_login_attempts attempt
  where attempt.origin_hash = p_origin_hash
    and not attempt.succeeded
    and not attempt.blocked
    and attempt.attempted_at >= clock_timestamp() - interval '15 minutes';

  if v_passport_failures >= 5 or v_origin_failures >= 20 then
    v_block_scope := case
      when v_passport_failures >= 5 and v_origin_failures >= 20 then 'both'
      when v_passport_failures >= 5 then 'passport'
      else 'origin'
    end;

    if not exists (
      select 1
      from public.patient_portal_login_attempts attempt
      where attempt.blocked
        and attempt.attempted_at >= clock_timestamp() - interval '15 minutes'
        and (
          (v_block_scope = 'passport' and attempt.passport_hash = v_passport_hash and attempt.block_scope = 'passport')
          or (v_block_scope = 'origin' and attempt.origin_hash = p_origin_hash and attempt.block_scope = 'origin')
          or (v_block_scope = 'both' and attempt.passport_hash = v_passport_hash and attempt.origin_hash = p_origin_hash and attempt.block_scope = 'both')
        )
    ) then
      insert into public.patient_portal_login_attempts (
        passport_hash,
        origin_hash,
        client_hash,
        blocked,
        block_scope
      ) values (
        v_passport_hash,
        p_origin_hash,
        p_client_hash,
        true,
        v_block_scope
      );

      insert into public.audit_logs (
        actor_user_id,
        actor_passport,
        action,
        entity_name,
        entity_id,
        new_values
      ) values (
        null,
        null,
        'PATIENT_PORTAL_RATE_LIMITED',
        'patient_portal',
        null,
        jsonb_build_object('scope', v_block_scope)
      );
    end if;

    return jsonb_build_object('ok', false, 'blocked', true);
  end if;

  select patient.*
  into v_patient
  from public.patients patient
  where patient.passport = v_passport
    and patient.birth_date = p_birth_date
  limit 1;

  if not found then
    insert into public.patient_portal_login_attempts (
      passport_hash,
      origin_hash,
      client_hash
    ) values (
      v_passport_hash,
      p_origin_hash,
      p_client_hash
    );

    return jsonb_build_object('ok', false, 'blocked', false);
  end if;

  v_expires_at := clock_timestamp() + interval '12 hours';

  insert into public.patient_portal_sessions (
    patient_id,
    token_hash,
    expires_at
  ) values (
    v_patient.id,
    p_token_hash,
    v_expires_at
  );

  insert into public.patient_portal_login_attempts (
    patient_id,
    passport_hash,
    origin_hash,
    client_hash,
    succeeded
  ) values (
    v_patient.id,
    v_passport_hash,
    p_origin_hash,
    p_client_hash,
    true
  );

  insert into public.audit_logs (
    actor_user_id,
    actor_passport,
    action,
    entity_name,
    entity_id,
    new_values
  ) values (
    null,
    null,
    'PATIENT_PORTAL_LOGIN',
    'patient_portal',
    v_patient.id::text,
    jsonb_build_object('outcome', 'success')
  );

  return jsonb_build_object(
    'ok', true,
    'blocked', false,
    'expires_at', v_expires_at
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_exam_detail(p_token_hash text, p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_images jsonb := '[]'::jsonb;
  v_session record;
  v_target record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select exam.id, exam.requested_at, exam.completed_at, exam.status,
    exam.final_report_snapshot, exam_type.name as type_name, category.name as category_name
  into v_target
  from public.clinical_exams exam
  join public.exam_types exam_type on exam_type.id = exam.exam_type_id
  join public.exam_categories category on category.id = exam_type.category_id
  where exam.id = p_exam_id and exam.patient_id = v_session.patient_id;

  if not found then
    return jsonb_build_object('authenticated', true, 'found', false);
  end if;

  if v_target.status = 'completed' and v_target.final_report_snapshot is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', image.id,
      'storage_path', image.storage_path,
      'original_filename', image.original_filename,
      'mime_type', image.mime_type,
      'sort_order', image.sort_order,
      'caption', image.caption,
      'source', image.source,
      'created_at', image.created_at
    ) order by image.sort_order, image.created_at, image.id), '[]'::jsonb)
    into v_images
    from public.clinical_exam_images image
    where image.exam_id = v_target.id
      and image.removed_at is null
      and exists (
        select 1
        from jsonb_array_elements(coalesce(v_target.final_report_snapshot -> 'images', '[]'::jsonb)) snapshot_image
        where snapshot_image ->> 'id' = image.id::text
      );
  end if;

  return jsonb_build_object(
    'authenticated', true,
    'found', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'exam', jsonb_build_object(
      'id', v_target.id,
      'type', v_target.type_name,
      'category', v_target.category_name,
      'occurred_at', v_target.requested_at,
      'completed_at', v_target.completed_at,
      'status', v_target.status
    ),
    'final_report_snapshot', case when v_target.status = 'completed' then v_target.final_report_snapshot else null end,
    'images', case when v_target.status = 'completed' then v_images else '[]'::jsonb end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_exam_document_state(p_token_hash text, p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  if not exists (
    select 1 from public.clinical_exams exam
    where exam.id = p_exam_id
      and exam.patient_id = v_session.patient_id
      and exam.status = 'completed'
      and exam.final_report_snapshot is not null
  ) then
    return jsonb_build_object('authenticated', true, 'found', false);
  end if;

  return jsonb_build_object(
    'authenticated', true,
    'found', true,
    'state', private.clinical_exam_document_state_json(p_exam_id)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_exam_image(p_token_hash text, p_exam_id bigint, p_image_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_result jsonb;
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select jsonb_build_object(
    'storage_path', image.storage_path,
    'mime_type', image.mime_type,
    'file_size', image.file_size
  ) into v_result
  from public.clinical_exams exam
  join public.clinical_exam_images image on image.exam_id = exam.id
  where exam.id = p_exam_id
    and exam.patient_id = v_session.patient_id
    and exam.status = 'completed'
    and exam.final_report_snapshot is not null
    and image.id = p_image_id
    and image.removed_at is null
    and exists (
      select 1
      from jsonb_array_elements(coalesce(exam.final_report_snapshot -> 'images', '[]'::jsonb)) snapshot_image
      where snapshot_image ->> 'id' = image.id::text
    );

  if v_result is null then
    return jsonb_build_object('authenticated', true, 'found', false);
  end if;

  return jsonb_build_object('authenticated', true, 'found', true, 'image', v_result);
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_exam_page(p_token_hash text, p_cursor_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id bigint DEFAULT NULL::bigint, p_status_group text DEFAULT 'all'::text, p_limit integer DEFAULT 15)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_has_more boolean;
  v_items jsonb;
  v_limit integer := least(greatest(coalesce(p_limit, 15), 1), 30);
  v_next_at timestamptz;
  v_next_id bigint;
  v_session record;
  v_status_group text := coalesce(nullif(trim(p_status_group), ''), 'all');
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;
  if (p_cursor_at is null) <> (p_cursor_id is null)
     or (p_cursor_id is not null and p_cursor_id < 1)
     or v_status_group not in ('all', 'in_progress', 'completed') then
    raise exception 'Parâmetros inválidos.' using errcode = '22023';
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  with page_rows as materialized (
    select exam.id, exam.requested_at, exam.completed_at, exam.status,
      exam_type.name as type_name, category.name as category_name
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    join public.exam_categories category on category.id = exam_type.category_id
    where exam.patient_id = v_session.patient_id
      and (
        v_status_group = 'all'
        or (v_status_group = 'completed' and exam.status = 'completed')
        or (v_status_group = 'in_progress' and exam.status in ('requested', 'in_progress', 'awaiting_review'))
      )
      and (p_cursor_at is null or (exam.requested_at, exam.id) < (p_cursor_at, p_cursor_id))
    order by exam.requested_at desc, exam.id desc
    limit v_limit + 1
  ), visible_rows as materialized (
    select * from page_rows order by requested_at desc, id desc limit v_limit
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'id', visible.id,
      'type', visible.type_name,
      'category', visible.category_name,
      'occurred_at', visible.requested_at,
      'completed_at', visible.completed_at,
      'status', visible.status
    ) order by visible.requested_at desc, visible.id desc), '[]'::jsonb),
    (select count(*) > v_limit from page_rows),
    (select requested_at from visible_rows order by requested_at, id limit 1),
    (select id from visible_rows order by requested_at, id limit 1)
  into v_items, v_has_more, v_next_at, v_next_id
  from visible_rows visible;

  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'items', v_items,
    'next_cursor', case when v_has_more then jsonb_build_object('occurred_at', v_next_at, 'id', v_next_id) else null end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_health_plan_page(p_token_hash text, p_cursor_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id bigint DEFAULT NULL::bigint, p_limit integer DEFAULT 12)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_current record;
  v_has_more boolean;
  v_items jsonb;
  v_limit integer := least(greatest(coalesce(p_limit, 12), 1), 30);
  v_next_at timestamptz;
  v_next_id bigint;
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;
  if (p_cursor_at is null) <> (p_cursor_id is null)
     or (p_cursor_id is not null and p_cursor_id < 1) then
    raise exception 'Cursor inválido.' using errcode = '22023';
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_current
  from private.patient_portal_health_plan_state(v_session.patient_id);

  with plan_events as materialized (
    select
      request.id,
      coalesce(request.reviewed_at, request.requested_at) as event_at,
      request.requested_at,
      request.reviewed_at,
      request.status,
      request.coverage_start,
      request.coverage_end,
      case
        when request.status = 'approved'
          and exists (
            select 1
            from public.patient_health_plan_requests previous
            where previous.patient_id = request.patient_id
              and previous.status = 'approved'
              and previous.id < request.id
          ) then 'renewed'
        when request.status = 'approved' then 'activated'
        when request.status = 'rejected' then 'not_approved'
        else 'requested'
      end as event_type
    from public.patient_health_plan_requests request
    where request.patient_id = v_session.patient_id
  ), page_rows as materialized (
    select event.*
    from plan_events event
    where p_cursor_at is null
      or (event.event_at, event.id) < (p_cursor_at, p_cursor_id)
    order by event.event_at desc, event.id desc
    limit v_limit + 1
  ), visible_rows as materialized (
    select *
    from page_rows
    order by event_at desc, id desc
    limit v_limit
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'key', 'health-plan:' || visible.id::text,
      'status', visible.status,
      'event', visible.event_type,
      'occurred_at', visible.event_at,
      'requested_at', visible.requested_at,
      'reviewed_at', visible.reviewed_at,
      'coverage_start', visible.coverage_start,
      'coverage_end', visible.coverage_end
    ) order by visible.event_at desc, visible.id desc), '[]'::jsonb),
    (select count(*) > v_limit from page_rows),
    (select event_at from visible_rows order by event_at, id limit 1),
    (select id from visible_rows order by event_at, id limit 1)
  into v_items, v_has_more, v_next_at, v_next_id
  from visible_rows visible;

  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object(
      'name', v_session.patient_name,
      'passport', v_session.patient_passport
    ),
    'current', jsonb_build_object(
      'status', v_current.status,
      'activated_at', v_current.activated_at,
      'valid_until', v_current.valid_until,
      'pending_requested_at', v_current.pending_requested_at
    ),
    'items', v_items,
    'next_cursor', case
      when v_has_more then jsonb_build_object('occurred_at', v_next_at, 'id', v_next_id)
      else null
    end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_history_page(p_token_hash text, p_cursor_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_key text DEFAULT NULL::text, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_has_more boolean;
  v_items jsonb;
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_next_at timestamptz;
  v_next_key text;
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;
  if (p_cursor_at is null) <> (p_cursor_key is null)
     or (p_cursor_key is not null and char_length(p_cursor_key) > 128) then
    raise exception 'Cursor inválido.' using errcode = '22023';
  end if;

  select *
  into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  with events as (
    select
      attendance.created_at as event_at,
      'attendance:' || attendance.id::text as event_key,
      'attendance'::text as event_type,
      'Atendimento realizado'::text as title,
      coalesce(professional.display_name, 'Profissional')::text as description,
      professional.display_name as professional_name,
      position.name as professional_position,
      attendance.total as amount,
      attendance.id as attendance_id
    from public.attendances attendance
    left join public.profiles professional on professional.user_id = attendance.performed_by
    left join public.staff_positions position on position.id = professional.position_id
    where attendance.patient_id = v_session.patient_id
      and attendance.status = 'completed'

    union all

    select
      exam.completed_at,
      'exam:' || exam.id::text,
      'exam',
      exam_type.name || ' concluído',
      coalesce(responsible.display_name, 'Profissional responsável'),
      responsible.display_name,
      position.name,
      null::numeric,
      null::bigint
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    left join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
    left join public.staff_positions position on position.id = responsible.position_id
    where exam.patient_id = v_session.patient_id
      and exam.status = 'completed'
      and exam.completed_at is not null

    union all

    select
      cast_record.applied_at,
      'cast-applied:' || cast_record.id::text,
      'cast',
      'Gesso aplicado — ' || private.clinical_cast_location_label(cast_record.body_region, cast_record.laterality),
      coalesce(applied.display_name, 'Profissional responsável'),
      applied.display_name,
      position.name,
      null::numeric,
      null::bigint
    from public.clinical_casts cast_record
    left join public.profiles applied on applied.user_id = cast_record.applied_by
    left join public.staff_positions position on position.id = applied.position_id
    where cast_record.patient_id = v_session.patient_id
      and cast_record.status in ('in_use', 'removed')

    union all

    select
      cast_record.removed_at,
      'cast-removed:' || cast_record.id::text,
      'cast',
      'Gesso retirado — ' || private.clinical_cast_location_label(cast_record.body_region, cast_record.laterality),
      coalesce(removed.display_name, 'Profissional responsável'),
      removed.display_name,
      position.name,
      null::numeric,
      null::bigint
    from public.clinical_casts cast_record
    left join public.profiles removed on removed.user_id = cast_record.removed_by
    left join public.staff_positions position on position.id = removed.position_id
    where cast_record.patient_id = v_session.patient_id
      and cast_record.status = 'removed'
      and cast_record.removed_at is not null

    union all

    select
      request.reviewed_at,
      'health-plan:' || request.id::text,
      'health_plan',
      case
        when request.coverage_start > request.reviewed_at + interval '1 minute'
          then 'Plano de Saúde renovado'
        else 'Plano de Saúde ativado'
      end,
      'Cobertura até ' || to_char(request.coverage_end at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
      null::text,
      null::text,
      null::numeric,
      null::bigint
    from public.patient_health_plan_requests request
    where request.patient_id = v_session.patient_id
      and request.status = 'approved'
      and request.reviewed_at is not null
  ), page_rows as materialized (
    select event.*
    from events event
    where event.event_at is not null
      and (
        p_cursor_at is null
        or (event.event_at, event.event_key) < (p_cursor_at, p_cursor_key)
      )
    order by event.event_at desc, event.event_key desc
    limit v_limit + 1
  ), visible_rows as materialized (
    select *
    from page_rows
    order by event_at desc, event_key desc
    limit v_limit
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'key', visible.event_key,
          'occurred_at', visible.event_at,
          'type', visible.event_type,
          'title', visible.title,
          'description', visible.description,
          'professional_name', visible.professional_name,
          'professional_position', visible.professional_position,
          'amount', visible.amount,
          'attendance_id', visible.attendance_id
        ) order by visible.event_at desc, visible.event_key desc
      ),
      '[]'::jsonb
    ),
    (select count(*) > v_limit from page_rows),
    (select event_at from visible_rows order by event_at, event_key limit 1),
    (select event_key from visible_rows order by event_at, event_key limit 1)
  into v_items, v_has_more, v_next_at, v_next_key
  from visible_rows visible;

  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object(
      'name', v_session.patient_name,
      'passport', v_session.patient_passport
    ),
    'items', v_items,
    'next_cursor', case
      when v_has_more then jsonb_build_object('occurred_at', v_next_at, 'key', v_next_key)
      else null
    end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_import_partnership_people(p_token_hash text, p_partnership_id bigint, p_people jsonb, p_source text DEFAULT 'batch'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_patient_id bigint := private.partnership_portal_actor(p_token_hash, p_partnership_id, true);
begin
  return private.partnership_apply_people(p_partnership_id, p_people, 'partnership_responsible', null, v_actor_patient_id, p_source);
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_partnership_member_page(p_token_hash text, p_partnership_id bigint, p_filter text DEFAULT 'all'::text, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_patient_id bigint := private.partnership_portal_actor(p_token_hash, p_partnership_id, false);
  v_filter text := lower(btrim(coalesce(p_filter, 'all')));
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
  v_partnership public.partnerships%rowtype;
  v_patient public.patients%rowtype;
begin
  if v_filter not in ('all', 'linked', 'pending_registration', 'name_review') then
    raise exception 'Filtro inválido.' using errcode = '22023';
  end if;
  select * into v_partnership from public.partnerships where id = p_partnership_id;
  select * into v_patient from public.patients where id = v_actor_patient_id;

  with combined as materialized (
    select 'membership'::text as record_type, membership.id, patient.passport, patient.name,
      'linked'::text as status, membership.linked_at as occurred_at
    from public.patient_partnerships membership
    join public.patients patient on patient.id = membership.patient_id
    where membership.partnership_id = p_partnership_id and membership.status = 'active'
    union all
    select 'pending'::text, pending.id, pending.passport, pending.informed_name,
      pending.status, pending.created_at
    from public.partnership_pending_beneficiaries pending
    where pending.partnership_id = p_partnership_id and pending.status in ('pending_registration', 'name_review')
  ), filtered as (
    select * from combined row
    where (v_filter = 'all' or row.status = v_filter)
      and (v_search = '' or lower(row.name) like '%' || v_search || '%' or row.passport like v_search || '%')
  ), page_rows as (
    select * from filtered row order by lower(row.name), row.passport, row.record_type, row.id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object('name', v_patient.name, 'passport', v_patient.passport),
    'partnership', jsonb_build_object('id', v_partnership.id, 'name', v_partnership.name, 'status', v_partnership.status),
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'record_key', case when row.record_type = 'membership' then 'm:' else 'p:' end || row.id::text,
      'name', row.name,
      'passport', row.passport,
      'status', row.status,
      'occurred_at', row.occurred_at
    ) order by lower(row.name), row.passport, row.record_type, row.id), '[]'::jsonb),
    'total', (select count(*)::integer from filtered),
    'limit', v_limit,
    'offset', v_offset
  ) into v_result
  from page_rows row;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_partnership_page(p_token_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session record;
  v_result jsonb;
begin
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if not found then return jsonb_build_object('authenticated', false); end if;

  with responsible as materialized (
    select partnership.*
    from public.partnerships partnership
    where partnership.responsible_patient_id = v_session.patient_id
  ), member_counts as materialized (
    select membership.partnership_id, count(*)::integer as linked
    from public.patient_partnerships membership
    join responsible partnership on partnership.id = membership.partnership_id
    where membership.status = 'active'
    group by membership.partnership_id
  ), pending_counts as materialized (
    select pending.partnership_id,
      count(*) filter (where pending.status = 'pending_registration')::integer as pending_registration,
      count(*) filter (where pending.status = 'name_review')::integer as name_review
    from public.partnership_pending_beneficiaries pending
    join responsible partnership on partnership.id = pending.partnership_id
    where pending.status in ('pending_registration', 'name_review')
    group by pending.partnership_id
  )
  select jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', partnership.id,
      'name', partnership.name,
      'status', partnership.status,
      'linked', coalesce(member_counts.linked, 0),
      'pending_registration', coalesce(pending_counts.pending_registration, 0),
      'name_review', coalesce(pending_counts.name_review, 0),
      'total_informed', coalesce(member_counts.linked, 0) + coalesce(pending_counts.pending_registration, 0) + coalesce(pending_counts.name_review, 0)
    ) order by (partnership.status = 'active') desc, lower(partnership.name)), '[]'::jsonb)
  ) into v_result
  from responsible partnership
  left join member_counts on member_counts.partnership_id = partnership.id
  left join pending_counts on pending_counts.partnership_id = partnership.id;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_register_clinical_exam_document(p_token_hash text, p_exam_id bigint, p_document_id uuid, p_storage_path text, p_file_size bigint, p_pixel_width integer, p_pixel_height integer, p_render_version text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_document public.clinical_exam_documents;
  v_session record;
  v_target public.clinical_exams;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select exam.* into v_target
  from public.clinical_exams exam
  where exam.id = p_exam_id and exam.patient_id = v_session.patient_id
  for update;

  if not found or v_target.status <> 'completed' or v_target.final_report_snapshot is null then
    return jsonb_build_object('authenticated', true, 'found', false);
  end if;

  if p_document_id is null
     or p_render_version <> 'exam-document-png-v4'
     or p_storage_path <> format('clinical-exams/%s/documents/%s.png', p_exam_id, p_document_id)
     or p_file_size not between 1 and 12582912
     or p_pixel_width not between 900 and 1400
     or p_pixel_height not between 400 and 14000 then
    raise exception 'Metadados inválidos para a imagem do documento.' using errcode = '22023';
  end if;

  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'clinical-exam-documents'
      and object.name = p_storage_path
      and lower(coalesce(object.metadata ->> 'mimetype', '')) = 'image/png'
      and coalesce((object.metadata ->> 'size')::bigint, 0) = p_file_size
  ) then
    raise exception 'A imagem do documento ainda não foi confirmada no Storage.';
  end if;

  insert into public.clinical_exam_documents (
    id, exam_id, storage_path, mime_type, file_size, pixel_width, pixel_height,
    render_version, created_by, created_by_patient_id
  ) values (
    p_document_id, p_exam_id, p_storage_path, 'image/png', p_file_size, p_pixel_width, p_pixel_height,
    p_render_version, null, v_session.patient_id
  ) on conflict (exam_id, render_version) do nothing;

  select document.* into v_document
  from public.clinical_exam_documents document
  where document.exam_id = p_exam_id and document.render_version = p_render_version
  limit 1;

  if v_document.id is null then
    raise exception 'Não foi possível registrar a imagem do documento.';
  end if;

  return jsonb_build_object(
    'authenticated', true,
    'found', true,
    'state', private.clinical_exam_document_state_json(p_exam_id)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_revoke_session(p_token_hash text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_patient_id bigint;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  update public.patient_portal_sessions session
  set revoked_at = clock_timestamp()
  where session.token_hash = p_token_hash
    and session.revoked_at is null
    and session.expires_at > clock_timestamp()
  returning session.patient_id into v_patient_id;

  if v_patient_id is null then
    return false;
  end if;

  insert into public.audit_logs (
    actor_user_id,
    actor_passport,
    action,
    entity_name,
    entity_id,
    new_values
  ) values (
    null,
    null,
    'PATIENT_PORTAL_LOGOUT',
    'patient_portal',
    v_patient_id::text,
    jsonb_build_object('outcome', 'revoked')
  );

  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_session_me(p_token_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session record;
begin
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if not found then return jsonb_build_object('authenticated', false); end if;
  return jsonb_build_object(
    'authenticated', true,
    'name', v_session.patient_name,
    'passport', v_session.patient_passport,
    'expires_at', v_session.expires_at,
    'manages_partnerships', exists (
      select 1 from public.partnerships partnership
      where partnership.responsible_patient_id = v_session.patient_id
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_summary(p_token_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_metrics record;
  v_result jsonb;
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if not found then return jsonb_build_object('authenticated', false); end if;
  select * into v_metrics from private.patient_portal_attendance_metrics(v_session.patient_id);

  with last_attendance as (
    select attendance.id, attendance.created_at, attendance.total, professional.display_name as professional_name
    from public.attendances attendance
    left join public.profiles professional on professional.user_id = attendance.performed_by
    where attendance.patient_id = v_session.patient_id and attendance.status = 'completed'
    order by attendance.created_at desc, attendance.id desc limit 1
  ), health_plan_payload as (
    select jsonb_build_object(
      'status', plan.status,
      'valid_until', plan.valid_until
    ) as value
    from private.patient_portal_health_plan_state(v_session.patient_id) plan
  ), recent_exams as materialized (
    select exam.id, exam.requested_at, exam.status, exam_type.name as type_name
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    where exam.patient_id = v_session.patient_id
    order by exam.requested_at desc, exam.id desc limit 3
  ), recent_exams_payload as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', exam.id,
      'type', exam.type_name,
      'occurred_at', exam.requested_at,
      'status', exam.status
    ) order by exam.requested_at desc, exam.id desc), '[]'::jsonb) as value
    from recent_exams exam
  ), active_casts as materialized (
    select cast_record.id, cast_record.body_region, cast_record.laterality,
      cast_record.applied_at, cast_record.expected_removal_at
    from public.clinical_casts cast_record
    where cast_record.patient_id = v_session.patient_id and cast_record.status = 'in_use'
    order by cast_record.expected_removal_at, cast_record.id
  ), active_casts_payload as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'body_region', cast_record.body_region,
      'laterality', cast_record.laterality,
      'applied_at', cast_record.applied_at,
      'expected_removal_at', cast_record.expected_removal_at
    ) order by cast_record.expected_removal_at, cast_record.id), '[]'::jsonb) as value
    from active_casts cast_record
  )
  select jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'summary', jsonb_build_object(
      'total_attendances', v_metrics.total_attendances,
      'lifetime_spent', v_metrics.lifetime_spent,
      'last_attendance', case when latest.id is null then null else jsonb_build_object(
        'occurred_at', latest.created_at, 'total', latest.total, 'professional_name', latest.professional_name
      ) end
    ),
    'health_plan', plan.value,
    'recent_exams', exams.value,
    'active_casts', casts.value
  ) into v_result
  from (select true) singleton
  left join last_attendance latest on true
  cross join health_plan_payload plan
  cross join recent_exams_payload exams
  cross join active_casts_payload casts;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_portal_unlink_partnership_member(p_token_hash text, p_partnership_id bigint, p_record_key text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_patient_id bigint := private.partnership_portal_actor(p_token_hash, p_partnership_id, true);
  v_membership public.patient_partnerships%rowtype;
  v_id bigint;
begin
  if p_record_key !~ '^m:[0-9]+$' then raise exception 'Beneficiário inválido.' using errcode = '22023'; end if;
  v_id := substring(p_record_key from 3)::bigint;
  select * into v_membership from public.patient_partnerships
  where id = v_id and partnership_id = p_partnership_id for update;
  if not found or v_membership.status <> 'active' then raise exception 'Beneficiário ativo não localizado.' using errcode = '22023'; end if;
  update public.patient_partnerships set status = 'inactive', unlinked_at = now(),
    unlinked_by_type = 'partnership_responsible', unlinked_by_patient_id = v_actor_patient_id,
    unlink_reason = 'Removido pelo responsável da parceria.'
  where id = v_id;
  perform private.partnership_audit('PARTNERSHIP_MEMBER_REMOVED', 'patient_partnerships', v_id::text,
    'partnership_responsible', null, v_actor_patient_id, null,
    jsonb_build_object('partnership_id', p_partnership_id, 'patient_id', v_membership.patient_id));
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.patient_profile_summary(p_patient_id bigint)
 RETURNS TABLE(total_attendances bigint, last_attendance_at timestamp with time zone, total_purchases bigint, recent_procedures jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
  if not private.has_permission((select auth.uid()), 'patients.view') then
    raise exception 'Você não possui permissão para consultar pacientes.';
  end if;

  return query
  select
    count(*) filter (where attendance.status = 'completed')::bigint,
    max(attendance.created_at) filter (where attendance.status = 'completed'),
    count(*) filter (
      where attendance.status = 'completed'
        and exists (
          select 1
          from public.attendance_items as item
          join public.service_catalog as service on service.id = item.service_id
          where item.attendance_id = attendance.id
            and lower(service.category) in ('insumos', 'medicamentos', 'produtos', 'convênios')
        )
    )::bigint,
    coalesce((
      select jsonb_agg(recent.item order by recent.created_at desc, recent.id desc)
      from (
        select
          item.id,
          attendance_item.created_at,
          jsonb_build_object(
            'id', item.id,
            'attendance_id', attendance_item.id,
            'name', item.service_name,
            'category', service.category,
            'date', attendance_item.created_at
          ) as item
        from public.attendance_items as item
        join public.attendances as attendance_item on attendance_item.id = item.attendance_id
        join public.service_catalog as service on service.id = item.service_id
        where attendance_item.patient_id = p_patient_id
          and attendance_item.status = 'completed'
          and lower(service.category) in ('atendimentos', 'exames')
        order by attendance_item.created_at desc, item.id desc
        limit 5
      ) as recent
    ), '[]'::jsonb)
  from public.attendances as attendance
  where attendance.patient_id = p_patient_id;
end;
$function$;


CREATE OR REPLACE FUNCTION public.prepare_professional_identity_regeneration(p_target_user_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_reason text := nullif(btrim(p_reason), '');
begin
  if not private.hpsm_identity_is_director_general(v_actor) then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;
  if v_reason is null or char_length(v_reason) not between 5 and 500 then
    raise exception 'Informe o motivo da regeneracao.' using errcode = '22023';
  end if;
  update public.professional_identities
  set signature_regeneration_reason = v_reason, updated_at = now()
  where user_id = p_target_user_id;
  if not found then raise exception 'Identidade profissional nao localizada.' using errcode = 'P0002'; end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.professional_identity_generation_context(p_target_user_id uuid DEFAULT NULL::uuid, p_operation text DEFAULT 'initial'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_is_director boolean := private.hpsm_identity_is_director_general(v_actor);
  v_target uuid := coalesce(p_target_user_id, v_actor);
  v_result jsonb;
begin
  if p_operation not in ('initial', 'regenerate', 'reprocess', 'status') then
    raise exception 'Operacao de identidade invalida.' using errcode = '22023';
  end if;
  if v_target <> v_actor and not v_is_director then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;
  if p_operation in ('regenerate', 'reprocess') and not v_is_director then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'actor_id', v_actor,
    'target_user_id', profile.user_id,
    'display_name', profile.display_name,
    'passport', profile.passport,
    'profile_status', profile.status,
    'must_change_password', profile.must_change_password,
    'crm_code', identity.crm_code,
    'registration_date', identity.registration_date,
    'status', identity.status,
    'generation_version', identity.generation_version,
    'signature_image_path', identity.signature_image_path,
    'rubric_image_path', identity.rubric_image_path,
    'is_director_general', v_is_director
  ) into v_result
  from public.profiles profile
  join public.professional_identities identity on identity.user_id = profile.user_id
  where profile.user_id = v_target;

  if v_result is null then
    raise exception 'Profissional nao localizado.' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.publish_notification_announcement(p_title text, p_body text, p_audience text, p_priority text, p_expires_at timestamp with time zone, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row public.notifications;
  v_actor_passport text;
begin
  if not (private.is_director_user(p_actor_id) or private.has_permission(p_actor_id, 'communications.manage')) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode publicar avisos.';
  end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 4 and 120 then
    raise exception using errcode = '22023', message = 'Informe um titulo entre 4 e 120 caracteres.';
  end if;
  if char_length(btrim(coalesce(p_body, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe uma mensagem entre 10 e 2000 caracteres.';
  end if;
  if p_audience not in ('all', 'directors', 'employees') then
    raise exception using errcode = '22023', message = 'Publico do aviso invalido.';
  end if;
  if p_priority not in ('normal', 'important', 'urgent') then
    raise exception using errcode = '22023', message = 'Prioridade do aviso invalida.';
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    raise exception using errcode = '22023', message = 'A validade deve estar no futuro.';
  end if;

  insert into public.notifications (
    kind, audience, priority, title, body, created_by, expires_at
  ) values (
    'announcement', p_audience, p_priority, btrim(p_title), btrim(p_body), p_actor_id, p_expires_at
  ) returning * into v_row;

  select passport into v_actor_passport
  from public.profiles
  where user_id = p_actor_id;

  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
  ) values (
    p_actor_id, v_actor_passport, 'INSERT', 'notifications', v_row.id::text, null, to_jsonb(v_row)
  );

  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_hr_hour_snapshot(p_employee_id uuid, p_reference_month date, p_reading_date date, p_total_minutes integer, p_note text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row public.rh_hour_snapshots;
  v_previous integer;
  v_next integer;
begin
  if not private.has_permission(p_actor_id, 'hr.hours.import') then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode lançar horas.';
  end if;

  if not exists (
    select 1 from public.profiles
    where user_id = p_employee_id and role_code <> 'diretor_geral'
  ) then
    raise exception using errcode = '22023', message = 'Colaborador inválido para o controle de horas.';
  end if;

  if p_reference_month is null
     or p_reading_date is null
     or p_total_minutes is null
     or p_reference_month <> date_trunc('month', p_reference_month)::date
     or p_reading_date < p_reference_month
     or p_reading_date >= (p_reference_month + interval '1 month')::date
     or p_total_minutes not between 0 and 60000 then
    raise exception using errcode = '22023', message = 'Competência, data ou total de horas inválido.';
  end if;

  if p_note is not null and char_length(p_note) > 500 then
    raise exception using errcode = '22023', message = 'A observação deve ter até 500 caracteres.';
  end if;

  select total_minutes into v_previous
  from public.rh_hour_snapshots
  where employee_id = p_employee_id
    and reference_month = p_reference_month
    and reading_date < p_reading_date
  order by reading_date desc
  limit 1;

  select total_minutes into v_next
  from public.rh_hour_snapshots
  where employee_id = p_employee_id
    and reference_month = p_reference_month
    and reading_date > p_reading_date
  order by reading_date asc
  limit 1;

  if v_previous is not null and p_total_minutes < v_previous then
    raise exception using errcode = '22023', message = 'O acumulado não pode ser menor que a leitura anterior do mês.';
  end if;
  if v_next is not null and p_total_minutes > v_next then
    raise exception using errcode = '22023', message = 'O acumulado não pode ultrapassar uma leitura posterior já registrada.';
  end if;

  insert into public.rh_hour_snapshots (
    employee_id, reference_month, reading_date, total_minutes, note, created_by, updated_by
  ) values (
    p_employee_id, p_reference_month, p_reading_date, p_total_minutes, nullif(btrim(p_note), ''), p_actor_id, p_actor_id
  )
  on conflict (employee_id, reference_month, reading_date) do update
  set total_minutes = excluded.total_minutes,
      note = excluded.note,
      updated_by = p_actor_id,
      updated_at = now()
  returning * into v_row;

  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_staff_course_status(p_course_id bigint, p_employee_id uuid, p_status text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row public.staff_course_records;
begin
  if not private.has_permission(p_actor_id, 'courses.completions.manage')
     or coalesce(private.current_position_level(p_actor_id), 0) < 11 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para registrar cursos.';
  end if;
  if p_status not in ('pending', 'completed')
     or not exists (select 1 from public.courses where id = p_course_id)
     or not exists (select 1 from public.profiles where user_id = p_employee_id and status <> 'inactive') then
    raise exception using errcode = '22023', message = 'Curso, colaborador ou situação inválida.';
  end if;
  insert into public.staff_course_records (
    course_id, employee_id, status, assigned_by, completed_by, completed_at
  ) values (
    p_course_id, p_employee_id, p_status, p_actor_id,
    case when p_status = 'completed' then p_actor_id else null end,
    case when p_status = 'completed' then now() else null end
  )
  on conflict (course_id, employee_id) do update set
    status = excluded.status,
    completed_by = excluded.completed_by,
    completed_at = excluded.completed_at,
    updated_at = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.refresh_staff_promotion_reviews(p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile record;
  v_created integer := 0;
  v_before bigint;
  v_after bigint;
begin
  if not private.has_permission(p_actor_id, 'progression.review')
     or coalesce(private.current_position_level(p_actor_id), 0) < 11 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para analisar progressões.';
  end if;
  for v_profile in
    select profile.user_id
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id
    where profile.status = 'active' and position.level between 1 and 9
  loop
    select id into v_before from public.staff_promotion_reviews
    where employee_id = v_profile.user_id and status in ('pending', 'deferred')
    order by created_at desc limit 1;
    v_after := private.ensure_staff_promotion_review(v_profile.user_id);
    if v_before is null and v_after is not null then v_created := v_created + 1; end if;
  end loop;
  return jsonb_build_object('created', v_created);
end;
$function$;

CREATE OR REPLACE FUNCTION public.register_clinical_exam_document(p_exam_id bigint, p_document_id uuid, p_storage_path text, p_file_size bigint, p_pixel_width integer, p_pixel_height integer, p_render_version text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_document public.clinical_exam_documents;
  v_share public.clinical_exam_document_shares;
  v_inserted_id uuid;
begin
  if not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select exam.* into v_exam
  from public.clinical_exams exam
  where exam.id = p_exam_id
  for update;

  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'completed' or v_exam.final_report_snapshot is null then
    raise exception 'A imagem compartilhável está disponível somente para exames concluídos.';
  end if;
  if p_document_id is null
     or p_render_version <> 'exam-document-png-v4'
     or p_storage_path <> format('clinical-exams/%s/documents/%s.png', p_exam_id, p_document_id)
     or p_file_size not between 1 and 12582912
     or p_pixel_width not between 900 and 1400
     or p_pixel_height not between 400 and 14000 then
    raise exception 'Metadados inválidos para a imagem do documento.';
  end if;

  if not exists (
    select 1
    from storage.objects object
    where object.bucket_id = 'clinical-exam-documents'
      and object.name = p_storage_path
      and lower(coalesce(object.metadata ->> 'mimetype', '')) = 'image/png'
      and coalesce((object.metadata ->> 'size')::bigint, 0) = p_file_size
  ) then
    raise exception 'A imagem do documento ainda não foi confirmada no Storage.';
  end if;

  insert into public.clinical_exam_documents (
    id, exam_id, storage_path, mime_type, file_size, pixel_width, pixel_height, render_version, created_by
  ) values (
    p_document_id, p_exam_id, p_storage_path, 'image/png', p_file_size, p_pixel_width, p_pixel_height, p_render_version, v_actor
  )
  on conflict (exam_id, render_version) do nothing
  returning id into v_inserted_id;

  select document.* into v_document
  from public.clinical_exam_documents document
  where document.exam_id = p_exam_id
    and document.render_version = p_render_version
  limit 1;

  if v_document.id is null then raise exception 'Não foi possível registrar a imagem do documento.'; end if;

  if v_inserted_id is not null then
    perform private.audit_exam_action(
      v_actor,
      'clinical_exam.document_png_generated',
      'clinical_exam_documents',
      v_document.id::text,
      null,
      jsonb_build_object(
        'exam_id', p_exam_id,
        'render_version', v_document.render_version,
        'file_size', v_document.file_size,
        'pixel_width', v_document.pixel_width,
        'pixel_height', v_document.pixel_height
      )
    );
  end if;

  select share.* into v_share
  from public.clinical_exam_document_shares share
  where share.exam_id = p_exam_id and share.revoked_at is null
  limit 1;

  if v_share.id is null then
    insert into public.clinical_exam_document_shares (exam_id, document_id, created_by)
    values (p_exam_id, v_document.id, v_actor)
    returning * into v_share;

    perform private.audit_exam_action(
      v_actor,
      'clinical_exam.document_link_created',
      'clinical_exam_document_shares',
      v_share.id::text,
      null,
      jsonb_build_object('exam_id', p_exam_id, 'document_id', v_document.id)
    );
  end if;

  return private.clinical_exam_document_state_json(p_exam_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.register_clinical_exam_image(p_exam_id bigint, p_image_id uuid, p_storage_path text, p_original_filename text, p_mime_type text, p_file_size bigint, p_caption text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_exam public.clinical_exams;
  v_image public.clinical_exam_images;
  v_expected_extension text;
  v_count integer;
begin
  select * into v_exam from public.clinical_exams where id = p_exam_id for update;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_exam.responsible_professional_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_exam.status <> 'in_progress' then raise exception 'As imagens só podem ser alteradas enquanto o exame está em andamento.'; end if;
  if v_exam.result_data->>'schema' <> 'hpsm.image_result.v1' then raise exception 'Este exame não utiliza imagens clínicas.'; end if;

  select count(*) into v_count from public.clinical_exam_images image where image.exam_id = p_exam_id and image.removed_at is null;
  if not (v_exam.result_data#>>'{template_snapshot,allows_multiple_images}')::boolean and v_count > 0 then
    raise exception 'Este tipo de exame aceita somente uma imagem.';
  end if;
  v_expected_extension := case p_mime_type when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' else null end;
  if p_image_id is null
     or v_expected_extension is null
     or p_file_size not between 1 and 10485760
     or p_storage_path <> 'clinical-exams/' || p_exam_id::text || '/' || p_image_id::text || '.' || v_expected_extension then
    raise exception 'Metadados da imagem inválidos.';
  end if;

  insert into public.clinical_exam_images (
    id, exam_id, storage_path, original_filename, mime_type, file_size,
    sort_order, caption, source, uploaded_by
  ) values (
    p_image_id, p_exam_id, p_storage_path, left(btrim(p_original_filename), 240), p_mime_type, p_file_size,
    (v_count + 1) * 10, nullif(left(btrim(p_caption), 500), ''), 'upload', v_actor
  ) returning * into v_image;
  update public.clinical_exams set updated_at = now() where id = p_exam_id;
  perform private.audit_exam_action(
    v_actor, 'clinical_exam.image_added', 'clinical_exam_images', v_image.id::text, null,
    jsonb_build_object('exam_id', v_image.exam_id, 'storage_path', v_image.storage_path, 'mime_type', v_image.mime_type, 'file_size', v_image.file_size, 'caption', v_image.caption, 'source', v_image.source)
  );
  return jsonb_build_object('id', v_image.id, 'exam_id', v_image.exam_id, 'storage_path', v_image.storage_path, 'original_filename', v_image.original_filename, 'mime_type', v_image.mime_type, 'file_size', v_image.file_size, 'sort_order', v_image.sort_order, 'caption', v_image.caption, 'source', v_image.source, 'uploaded_by', v_image.uploaded_by, 'created_at', v_image.created_at);
end;
$function$;

CREATE OR REPLACE FUNCTION public.remove_clinical_cast(p_cast_id bigint, p_removed_at timestamp with time zone, p_removal_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid;
  v_old public.clinical_casts;
  v_new public.clinical_casts;
  v_notes text := nullif(btrim(coalesce(p_removal_notes, '')), '');
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null or not private.has_permission(v_actor, 'casts.remove') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select * into v_old from public.clinical_casts where id = p_cast_id for update;
  if v_old.id is null then raise exception 'Registro de gesso não localizado.'; end if;
  if v_old.status <> 'in_use' then raise exception 'Este gesso já foi retirado ou cancelado.'; end if;
  if p_removed_at is null then raise exception 'Informe a data e hora da retirada.'; end if;
  if p_removed_at < v_old.applied_at then raise exception 'A retirada não pode ocorrer antes da aplicação.'; end if;
  if v_notes is not null and char_length(v_notes) > 1000 then
    raise exception 'A observação da retirada deve ter no máximo 1000 caracteres.';
  end if;

  update public.clinical_casts
  set status = 'removed', removed_at = p_removed_at, removed_by = v_actor, removal_notes = v_notes
  where id = p_cast_id
  returning * into v_new;

  perform private.audit_cast_action(
    v_actor, 'CAST_REMOVED', v_new.id,
    jsonb_build_object('status', v_old.status, 'expected_removal_at', v_old.expected_removal_at),
    jsonb_build_object(
      'status', v_new.status,
      'removed_at', v_new.removed_at,
      'removed_by', v_new.removed_by,
      'early_removal', v_new.removed_at < v_new.expected_removal_at,
      'removal_notes', v_new.removal_notes
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.remove_clinical_exam_image(p_image_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_exam public.clinical_exams;
  v_image public.clinical_exam_images;
begin
  select image.* into v_image from public.clinical_exam_images image where image.id = p_image_id for update;
  if v_image.id is null or v_image.removed_at is not null then raise exception 'Imagem não localizada.'; end if;
  select * into v_exam from public.clinical_exams where id = v_image.exam_id for update;
  if not private.can_perform_clinical_exam(v_actor, v_exam.responsible_professional_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_exam.status <> 'in_progress' then raise exception 'As imagens só podem ser alteradas enquanto o exame está em andamento.'; end if;

  update public.clinical_exam_images set removed_at = now(), removed_by = v_actor where id = p_image_id;
  update public.clinical_exams set updated_at = now() where id = v_image.exam_id;
  perform private.audit_exam_action(
    v_actor, 'clinical_exam.image_removed', 'clinical_exam_images', v_image.id::text,
    jsonb_build_object('exam_id', v_image.exam_id, 'storage_path', v_image.storage_path, 'caption', v_image.caption),
    jsonb_build_object('removed', true)
  );
  return v_image.storage_path;
end;
$function$;

CREATE OR REPLACE FUNCTION public.reopen_hr_week_closure(p_week_start date, p_reason text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_closure public.rh_week_closures;
  v_event public.rh_week_reopen_events;
begin
  if not private.has_permission(p_actor_id, 'hr.weeks.reopen') then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode reabrir semanas.';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe o motivo da reabertura entre 10 e 2000 caracteres.';
  end if;

  select * into v_closure
  from public.rh_week_closures
  where week_start = p_week_start
  for update;
  if not found or v_closure.status <> 'closed' then
    raise exception using errcode = 'P0002', message = 'A semana não está fechada.';
  end if;
  if exists (
    select 1
    from public.rh_warnings warning
    join public.rh_weekly_records record on record.id = warning.weekly_record_id
    where record.closure_id = v_closure.id and warning.status = 'active'
  ) then
    raise exception using errcode = 'P0001', message = 'Anule primeiro as advertências ativas vinculadas a esta semana.';
  end if;

  insert into public.rh_week_reopen_events (closure_id, reason, reopened_by)
  values (v_closure.id, btrim(p_reason), p_actor_id)
  returning * into v_event;

  update public.rh_week_closures
  set status = 'reopened', updated_at = now()
  where id = v_closure.id
  returning * into v_closure;

  update public.rh_weekly_records record
  set closure_status = case
        when exists (
          select 1 from public.rh_hour_justifications justification
          where justification.weekly_record_id = record.id and justification.status = 'pending'
        ) then 'justification_pending'
        when record.remaining_deficit_minutes > 0
             and not exists (
               select 1 from public.rh_hour_justifications justification
               where justification.weekly_record_id = record.id and justification.status in ('approved', 'rejected')
             ) then 'awaiting_justification'
        else 'ready'
      end,
      updated_at = now()
  where record.closure_id = v_closure.id;

  return jsonb_build_object('closure', to_jsonb(v_closure), 'event', to_jsonb(v_event));
end;
$function$;

CREATE OR REPLACE FUNCTION public.resolve_clinical_exam_document_share(p_share_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'exam_id', document.exam_id,
    'document_id', document.id,
    'storage_path', document.storage_path,
    'mime_type', document.mime_type,
    'file_size', document.file_size,
    'pixel_width', document.pixel_width,
    'pixel_height', document.pixel_height,
    'render_version', document.render_version
  )
  from public.clinical_exam_document_shares share
  join public.clinical_exam_documents document on document.id = share.document_id
  join public.clinical_exams exam on exam.id = share.exam_id
  where share.id = p_share_id
    and share.revoked_at is null
    and exam.status = 'completed'
    and exam.final_report_snapshot is not null
    and document.render_version = 'exam-document-png-v4'
  limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.restore_clinical_exam_image(p_image_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_image public.clinical_exam_images;
begin
  select * into v_image from public.clinical_exam_images where id = p_image_id for update;
  if v_image.id is null
     or v_image.removed_by is distinct from v_actor
     or v_image.removed_at is null
     or v_image.removed_at < now() - interval '5 minutes' then
    raise exception 'Não foi possível restaurar o metadado da imagem.';
  end if;
  perform 1 from public.clinical_exams where id = v_image.exam_id and status = 'in_progress' for update;
  if not found then raise exception 'O exame não permite alterações de imagem.'; end if;
  update public.clinical_exam_images set removed_at = null, removed_by = null where id = p_image_id;
  update public.clinical_exams set updated_at = now() where id = v_image.exam_id;
  perform private.audit_exam_action(v_actor, 'clinical_exam.image_removal_compensated', 'clinical_exam_images', p_image_id::text, jsonb_build_object('removed', true), jsonb_build_object('removed', false));
end;
$function$;

CREATE OR REPLACE FUNCTION public.review_clinical_exam(p_exam_id bigint, p_decision text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_version public.clinical_exam_report_versions;
  v_reviewed_at timestamptz := now();
  v_reviewer jsonb;
  v_final_snapshot jsonb;
  v_is_authority boolean;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  v_is_authority := coalesce(private.current_position_level(v_actor) between 11 and 14, false) and private.has_permission(v_actor, 'exams.review');
  if p_decision = 'approve' then
    if not v_is_authority and v_actor not in (v_old.requested_by, v_old.responsible_professional_id) then
      raise exception 'Acesso não autorizado.' using errcode = '42501';
    end if;
  elsif p_decision = 'return' then
    if not v_is_authority then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  else
    raise exception 'Decisão de revisão inválida.';
  end if;
  if v_old.status <> 'awaiting_review' then raise exception 'Este exame foi atualizado por outro profissional. Recarregue os dados para continuar.'; end if;

  select * into v_version from public.clinical_exam_report_versions version
  where version.exam_id = p_exam_id and version.decision = 'pending'
  order by version.version_number desc limit 1 for update;
  if v_version.id is null then
    insert into public.clinical_exam_report_versions (exam_id, version_number, snapshot, submitted_by, submitted_at)
    values (p_exam_id, coalesce((select max(version.version_number) + 1 from public.clinical_exam_report_versions version where version.exam_id = p_exam_id), 1),
      private.build_clinical_exam_report_snapshot(p_exam_id), v_old.responsible_professional_id, coalesce(v_old.submitted_for_review_at, v_old.updated_at))
    returning * into v_version;
  end if;
  select jsonb_build_object('id', reviewer.user_id, 'name', reviewer.display_name, 'position', position.name) into v_reviewer
  from public.profiles reviewer left join public.staff_positions position on position.id = reviewer.position_id where reviewer.user_id = v_actor;

  if p_decision = 'approve' then
    v_final_snapshot := v_version.snapshot || jsonb_build_object('reviewed_by', v_reviewer,
      'dates', coalesce(v_version.snapshot->'dates', '{}'::jsonb) || jsonb_build_object('completed_at', v_reviewed_at));
    update public.clinical_exam_report_versions set decision = 'approved', reviewed_by = v_actor, reviewed_at = v_reviewed_at where id = v_version.id;
    update public.clinical_exams set status = 'completed', reviewed_by = v_actor, completed_at = v_reviewed_at,
      correction_reason = null, final_report_snapshot = v_final_snapshot where id = p_exam_id returning * into v_new;
    insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
    values (p_exam_id, 'awaiting_review', 'completed', v_actor, 'Laudo revisado, aprovado e concluído.');
    perform private.audit_exam_action(v_actor, 'clinical_exam.completed', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
  else
    if nullif(btrim(p_reason), '') is null or char_length(btrim(p_reason)) < 2 then raise exception 'Informe o motivo da correção.'; end if;
    update public.clinical_exam_report_versions set decision = 'returned', reviewed_by = v_actor, reviewed_at = v_reviewed_at, review_reason = btrim(p_reason) where id = v_version.id;
    update public.clinical_exams set status = 'in_progress', submitted_for_review_at = null, reviewed_by = null,
      completed_at = null, correction_reason = btrim(p_reason), final_report_snapshot = null where id = p_exam_id returning * into v_new;
    insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
    values (p_exam_id, 'awaiting_review', 'in_progress', v_actor, btrim(p_reason));
    perform private.audit_exam_action(v_actor, 'clinical_exam.returned_for_correction', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.review_hr_absence(p_request_id bigint, p_decision text, p_effect text, p_note text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request public.rh_absence_requests;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode analisar justificativas.';
  end if;

  select * into v_request
  from public.rh_absence_requests
  where id = p_request_id
  for update;

  if not found or v_request.status <> 'pending' then
    raise exception using errcode = 'P0002', message = 'Justificativa não encontrada ou já analisada.';
  end if;
  if v_request.employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode analisar a própria justificativa.';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception using errcode = '22023', message = 'Decisão inválida.';
  end if;
  if p_decision = 'approved' and (p_effect is null or p_effect not in ('record_only', 'weekly_exemption')) then
    raise exception using errcode = '22023', message = 'Defina o efeito da justificativa aprovada.';
  end if;
  if p_decision = 'rejected' and char_length(btrim(coalesce(p_note, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe o motivo da recusa entre 10 e 2000 caracteres.';
  end if;
  if p_decision = 'approved' and p_note is not null and char_length(btrim(p_note)) > 2000 then
    raise exception using errcode = '22023', message = 'A observação deve ter até 2000 caracteres.';
  end if;

  update public.rh_absence_requests
  set status = p_decision,
      approval_effect = case when p_decision = 'approved' then p_effect else null end,
      review_note = case when nullif(btrim(p_note), '') is not null then btrim(p_note) else null end,
      reviewed_by = p_actor_id,
      reviewed_at = now(),
      updated_at = now()
  where id = p_request_id
  returning * into v_request;

  return to_jsonb(v_request);
end;
$function$;

CREATE OR REPLACE FUNCTION public.review_hr_hour_justification(p_justification_id bigint, p_decision text, p_credited_minutes integer, p_note text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row public.rh_hour_justifications;
  v_week public.rh_weekly_records;
  v_credit integer;
begin
  if not private.has_permission(p_actor_id, 'hr.justifications.review') then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode analisar justificativas de horas.';
  end if;

  select * into v_row
  from public.rh_hour_justifications
  where id = p_justification_id
  for update;
  if not found or v_row.status <> 'pending' then
    raise exception using errcode = 'P0002', message = 'Justificativa não encontrada ou já analisada.';
  end if;
  if v_row.employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode analisar a própria justificativa.';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception using errcode = '22023', message = 'Decisão inválida.';
  end if;

  select * into v_week
  from public.rh_weekly_records
  where id = v_row.weekly_record_id
  for update;
  if not found or v_week.closure_status <> 'justification_pending' then
    raise exception using errcode = 'P0001', message = 'O fechamento não está aguardando esta análise.';
  end if;

  if p_decision = 'approved' then
    v_credit := p_credited_minutes;
    if v_credit is null or v_credit not between 1 and v_row.deficit_minutes then
      raise exception using errcode = '22023', message = 'Informe quantas horas serão abonadas, sem ultrapassar o déficit.';
    end if;
  else
    v_credit := 0;
    if char_length(btrim(coalesce(p_note, ''))) not between 10 and 2000 then
      raise exception using errcode = '22023', message = 'Informe o motivo da recusa entre 10 e 2000 caracteres.';
    end if;
  end if;

  update public.rh_hour_justifications
  set status = p_decision,
      credited_minutes = v_credit,
      review_note = nullif(btrim(p_note), ''),
      reviewed_by = p_actor_id,
      reviewed_at = now(),
      updated_at = now()
  where id = v_row.id
  returning * into v_row;

  update public.rh_weekly_records
  set justification_minutes = least(v_credit, deficit_minutes),
      remaining_deficit_minutes = greatest(0, deficit_minutes - least(v_credit, deficit_minutes)),
      status = case
        when greatest(0, deficit_minutes - least(v_credit, deficit_minutes)) = 0 and v_credit > 0 then 'justified'
        when greatest(0, deficit_minutes - least(v_credit, deficit_minutes)) = 0 then 'met'
        else 'deficit'
      end,
      closure_status = 'ready',
      updated_at = now()
  where id = v_week.id;

  return jsonb_build_object(
    'justification', to_jsonb(v_row),
    'remaining_deficit_minutes', greatest(0, v_week.deficit_minutes - least(v_credit, v_week.deficit_minutes))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.review_hr_leave_request(p_request_id bigint, p_decision text, p_adjustments jsonb, p_note text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request public.rh_absence_requests;
  v_item jsonb;
  v_week_start date;
  v_minutes integer;
  v_seen_weeks date[] := array[]::date[];
  v_total integer := 0;
begin
  if not private.has_permission(p_actor_id, 'hr.absences.review') then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode analisar afastamentos.';
  end if;

  select * into v_request
  from public.rh_absence_requests
  where id = p_request_id
  for update;

  if not found or v_request.status <> 'pending' then
    raise exception using errcode = 'P0002', message = 'Afastamento não encontrado ou já analisado.';
  end if;
  if v_request.employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode analisar o próprio afastamento.';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception using errcode = '22023', message = 'Decisão inválida.';
  end if;

  if p_decision = 'approved' then
    if p_adjustments is null or jsonb_typeof(p_adjustments) <> 'array' or jsonb_array_length(p_adjustments) = 0 then
      raise exception using errcode = '22023', message = 'Informe as horas abatidas em pelo menos uma semana.';
    end if;
    for v_item in select value from jsonb_array_elements(p_adjustments)
    loop
      begin
        v_week_start := (v_item ->> 'week_start')::date;
        v_minutes := (v_item ->> 'deducted_minutes')::integer;
      exception when others then
        raise exception using errcode = '22023', message = 'Um dos abatimentos semanais é inválido.';
      end;
      if extract(isodow from v_week_start) <> 1
         or v_week_start + 6 < v_request.start_date
         or v_week_start > v_request.end_date
         or v_minutes not between 1 and 600
         or v_week_start = any(v_seen_weeks) then
        raise exception using errcode = '22023', message = 'Um dos abatimentos semanais é inválido ou repetido.';
      end if;
      v_seen_weeks := array_append(v_seen_weeks, v_week_start);
      v_total := v_total + v_minutes;
      insert into public.rh_leave_week_adjustments (
        leave_request_id, employee_id, week_start, deducted_minutes, approved_by
      ) values (
        v_request.id, v_request.employee_id, v_week_start, v_minutes, p_actor_id
      );
    end loop;
    if v_total <= 0 then
      raise exception using errcode = '22023', message = 'Informe ao menos um abatimento de horas.';
    end if;
  elsif char_length(btrim(coalesce(p_note, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe o motivo da recusa entre 10 e 2000 caracteres.';
  end if;

  update public.rh_absence_requests
  set status = p_decision,
      approval_effect = case when p_decision = 'approved' then 'weekly_adjustment' else null end,
      review_note = nullif(btrim(p_note), ''),
      reviewed_by = p_actor_id,
      reviewed_at = now(),
      updated_at = now()
  where id = p_request_id
  returning * into v_request;

  return jsonb_build_object(
    'leave', to_jsonb(v_request),
    'deducted_minutes', case when p_decision = 'approved' then v_total else 0 end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.review_partnership_pending(p_pending_id bigint, p_decision text, p_reason text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_pending public.partnership_pending_beneficiaries%rowtype;
  v_patient public.patients%rowtype;
  v_decision text := lower(btrim(coalesce(p_decision, '')));
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if v_decision not in ('confirm', 'reject') then raise exception 'Decisão inválida.' using errcode = '22023'; end if;
  select * into v_pending from public.partnership_pending_beneficiaries where id = p_pending_id for update;
  if not found or v_pending.status <> 'name_review' then raise exception 'Revisão pendente não localizada.' using errcode = '22023'; end if;
  if v_decision = 'reject' then
    if v_reason is null or char_length(v_reason) not between 2 and 500 then raise exception 'Informe o motivo da rejeição.' using errcode = '22023'; end if;
    update public.partnership_pending_beneficiaries set status = 'canceled', canceled_at = now(),
      canceled_by_type = 'professional', canceled_by_user_id = v_actor, cancellation_reason = v_reason
    where id = p_pending_id;
    perform private.partnership_audit('PARTNERSHIP_NAME_REVIEW_REJECTED', 'partnership_pending_beneficiaries', p_pending_id::text,
      'professional', v_actor, null, null,
      jsonb_build_object('partnership_id', v_pending.partnership_id, 'passport', v_pending.passport, 'reason', v_reason));
    return true;
  end if;

  select * into v_patient from public.patients where passport = v_pending.passport;
  if not found then raise exception 'O paciente deste passaporte não está cadastrado.' using errcode = '22023'; end if;
  insert into public.patient_partnerships (patient_id, partnership_id, linked_by_type, linked_by_user_id)
  values (v_patient.id, v_pending.partnership_id, 'professional', v_actor)
  on conflict (partnership_id, patient_id) where status = 'active' do nothing;
  update public.partnership_pending_beneficiaries set status = 'resolved', resolved_at = now(), resolved_patient_id = v_patient.id
  where id = p_pending_id;
  perform private.partnership_audit('PARTNERSHIP_NAME_REVIEW_CONFIRMED', 'partnership_pending_beneficiaries', p_pending_id::text,
    'professional', v_actor, null, null,
    jsonb_build_object('partnership_id', v_pending.partnership_id, 'patient_id', v_patient.id, 'passport', v_pending.passport));
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.review_patient_health_plan_request(p_request_id bigint, p_decision text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.review_patient_health_plan_request(p_request_id, p_decision, p_reason);
$function$;

CREATE OR REPLACE FUNCTION public.revoke_clinical_exam_document_share(p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_share public.clinical_exam_document_shares;
begin
  if not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select exam.* into v_exam
  from public.clinical_exams exam
  where exam.id = p_exam_id
  for update;

  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'completed' or v_exam.final_report_snapshot is null then
    raise exception 'O link está disponível somente para exames concluídos.';
  end if;

  select share.* into v_share
  from public.clinical_exam_document_shares share
  where share.exam_id = p_exam_id and share.revoked_at is null
  for update;

  if v_share.id is not null then
    update public.clinical_exam_document_shares
    set revoked_by = v_actor, revoked_at = now()
    where id = v_share.id;

    perform private.audit_exam_action(
      v_actor,
      'clinical_exam.document_link_revoked',
      'clinical_exam_document_shares',
      v_share.id::text,
      jsonb_build_object('active', true, 'exam_id', p_exam_id),
      jsonb_build_object('active', false, 'exam_id', p_exam_id)
    );
  end if;

  return private.clinical_exam_document_state_json(p_exam_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.revoke_temporary_permission(p_grant_id bigint, p_reason text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row public.user_permission_grants;
begin
  if not private.has_permission(p_actor_id, 'access.grants.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para revogar acessos.';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 1000 then
    raise exception using errcode = '22023', message = 'Informe o motivo da revogação.';
  end if;
  update public.user_permission_grants
  set revoked_at = now(), revoked_by = p_actor_id, revoked_reason = btrim(p_reason)
  where id = p_grant_id
    and revoked_at is null
    and (expires_at is null or expires_at > now())
  returning * into v_row;
  if not found then
    raise exception using errcode = 'P0002', message = 'Permissão não encontrada ou já encerrada.';
  end if;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_clinical_exam_draft(p_exam_id bigint, p_technique text, p_findings text, p_conclusion text, p_result_data jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_result_data jsonb;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_old.responsible_professional_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_old.status <> 'in_progress' then raise exception 'Este exame foi atualizado por outro profissional. Recarregue os dados para continuar.'; end if;
  if p_result_data is null or jsonb_typeof(p_result_data) <> 'object' then raise exception 'Dados adicionais inválidos.'; end if;

  v_result_data := case
    when v_old.result_data->>'schema' = 'hpsm.lab_result.v1' then private.normalize_lab_result(v_old.result_data, p_result_data)
    when v_old.result_data->>'schema' = 'hpsm.image_result.v1' then private.normalize_image_result(v_old.result_data, p_result_data)
    else p_result_data
  end;
  v_result_data := v_result_data || jsonb_build_object(
    'report_config_snapshot', v_old.result_data->'report_config_snapshot',
    'exam_type_snapshot', v_old.result_data->'exam_type_snapshot'
  );

  update public.clinical_exams
  set technique = nullif(btrim(p_technique), ''),
      findings = nullif(btrim(p_findings), ''),
      conclusion = nullif(btrim(p_conclusion), ''),
      result_data = v_result_data
  where id = p_exam_id
  returning * into v_new;

  if (to_jsonb(v_old) - 'updated_at') is distinct from (to_jsonb(v_new) - 'updated_at') then
    perform private.audit_exam_action(
      v_actor, 'clinical_exam.result_saved', 'clinical_exams', p_exam_id::text,
      jsonb_build_object('technique', v_old.technique, 'findings', v_old.findings, 'conclusion', v_old.conclusion, 'result_data', v_old.result_data),
      jsonb_build_object('technique', v_new.technique, 'findings', v_new.findings, 'conclusion', v_new.conclusion, 'result_data', v_new.result_data)
    );
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_dashboard_preferences(p_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.hpsm_dashboard_config_valid(p_config) then
    raise exception 'Configuração do Dashboard inválida.' using errcode = '22023';
  end if;

  insert into public.dashboard_preferences (
    user_id,
    config_version,
    layout_json,
    hidden_widgets,
    shortcuts_json
  ) values (
    v_actor,
    1,
    p_config -> 'layouts',
    p_config -> 'hiddenWidgets',
    p_config -> 'shortcuts'
  )
  on conflict (user_id) do update set
    config_version = excluded.config_version,
    layout_json = excluded.layout_json,
    hidden_widgets = excluded.hidden_widgets,
    shortcuts_json = excluded.shortcuts_json,
    updated_at = now();

  return jsonb_build_object(
    'configVersion', 1,
    'layouts', p_config -> 'layouts',
    'hiddenWidgets', p_config -> 'hiddenWidgets',
    'shortcuts', p_config -> 'shortcuts'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_partnership_status(p_partnership_id bigint, p_status text, p_reason text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_current public.partnerships%rowtype;
  v_status text := lower(btrim(coalesce(p_status, '')));
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if v_status not in ('active', 'inactive') then raise exception 'Status de parceria inválido.' using errcode = '22023'; end if;
  if v_status = 'inactive' and (v_reason is null or char_length(v_reason) not between 2 and 500) then
    raise exception 'Informe o motivo da inativação.' using errcode = '22023';
  end if;
  select * into v_current from public.partnerships where id = p_partnership_id for update;
  if not found then raise exception 'Parceria não localizada.' using errcode = '22023'; end if;
  if v_current.status = v_status then return true; end if;

  update public.partnerships set
    status = v_status,
    deactivated_at = case when v_status = 'inactive' then now() else null end,
    deactivated_by = case when v_status = 'inactive' then v_actor else null end,
    deactivation_reason = case when v_status = 'inactive' then v_reason else null end,
    updated_at = now(), updated_by = v_actor
  where id = p_partnership_id;
  insert into public.partnership_status_history (partnership_id, previous_status, status, reason, changed_by)
  values (p_partnership_id, v_current.status, v_status, v_reason, v_actor);
  perform private.partnership_audit(
    case when v_status = 'active' then 'PARTNERSHIP_REACTIVATED' else 'PARTNERSHIP_DEACTIVATED' end,
    'partnerships', p_partnership_id::text, 'professional', v_actor, null,
    jsonb_build_object('status', v_current.status), jsonb_build_object('status', v_status, 'reason', v_reason)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_staff_position_permissions(p_position_id bigint, p_permission_codes jsonb, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_code text;
  v_codes text[] := array[]::text[];
  v_level smallint;
begin
  if not private.has_permission(p_actor_id, 'access.manage')
     or private.current_position_level(p_actor_id) <> 14 then
    raise exception using errcode = '42501', message = 'Somente o Diretor Geral pode configurar os pacotes de acesso.';
  end if;
  select level into v_level from public.staff_positions where id = p_position_id;
  if v_level is null or p_permission_codes is null or jsonb_typeof(p_permission_codes) <> 'array' then
    raise exception using errcode = '22023', message = 'Cargo ou permissões inválidas.';
  end if;
  for v_code in select jsonb_array_elements_text(p_permission_codes)
  loop
    if not exists (select 1 from public.system_permissions where code = v_code)
       or v_code = any(v_codes) then
      raise exception using errcode = '22023', message = 'A lista contém permissão inválida ou repetida.';
    end if;
    v_codes := array_append(v_codes, v_code);
  end loop;
  if v_level = 14 and exists (
    select 1 from public.system_permissions permission where not (permission.code = any(v_codes))
  ) then
    raise exception using errcode = '23514', message = 'O Diretor Geral deve manter acesso total.';
  end if;
  if v_level <> 14 and v_codes && array['access.manage', 'access.grants.manage', 'succession.manage', 'settings.critical']::text[] then
    raise exception using errcode = '42501', message = 'Permissões críticas são exclusivas do Diretor Geral.';
  end if;
  delete from public.staff_position_permissions where position_id = p_position_id;
  insert into public.staff_position_permissions (position_id, permission_code, granted_by)
  select p_position_id, code, p_actor_id from unnest(v_codes) code;
  update public.staff_positions set updated_by = p_actor_id, updated_at = now() where id = p_position_id;
  return jsonb_build_object('position_id', p_position_id, 'permission_codes', to_jsonb(v_codes));
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_warning_progression_impact(p_warning_id bigint, p_impacts boolean, p_note text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row public.rh_warnings;
begin
  if not private.has_permission(p_actor_id, 'hr.warnings.progression') then
    raise exception using errcode = '42501', message = 'Você não pode alterar o impacto de advertências.';
  end if;
  if p_impacts is null or (p_note is not null and char_length(btrim(p_note)) not between 2 and 1000) then
    raise exception using errcode = '22023', message = 'Dados de impacto inválidos.';
  end if;
  update public.rh_warnings
  set impacts_progression = p_impacts,
      progression_flagged_by = case when p_impacts then p_actor_id else null end,
      progression_flagged_at = case when p_impacts then now() else null end,
      progression_impact_note = case when p_impacts then nullif(btrim(coalesce(p_note, '')), '') else null end,
      updated_at = now()
  where id = p_warning_id and status = 'active'
  returning * into v_row;
  if not found then
    raise exception using errcode = 'P0002', message = 'Advertência ativa não encontrada.';
  end if;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.start_clinical_exam(p_exam_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_result_data jsonb;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_old.responsible_professional_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_old.status <> 'requested' then raise exception 'Este exame foi atualizado por outro profissional. Recarregue os dados para continuar.'; end if;

  v_result_data := case
    when v_old.result_data->>'schema' in ('hpsm.lab_result.v1', 'hpsm.image_result.v1') then v_old.result_data
    else private.build_clinical_exam_result(v_old.exam_type_id)
  end;
  v_result_data := private.attach_clinical_exam_report_context(v_old.exam_type_id, v_result_data);

  update public.clinical_exams
  set status = 'in_progress', started_at = now(), result_data = v_result_data
  where id = p_exam_id
  returning * into v_new;

  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (p_exam_id, 'requested', 'in_progress', v_actor, 'Execução iniciada.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.started', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
end;
$function$;

CREATE OR REPLACE FUNCTION public.submit_clinical_exam_review(p_exam_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_missing text;
  v_missing_report text[] := array[]::text[];
  v_report_config jsonb;
  v_version integer;
  v_note text;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_old.responsible_professional_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_old.status <> 'in_progress' then raise exception 'Este exame foi atualizado por outro profissional. Recarregue os dados para continuar.'; end if;

  v_report_config := coalesce(v_old.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_old.exam_type_id));
  if coalesce((v_report_config#>>'{fields,technique,required}')::boolean, false) and v_old.technique is null then
    v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,technique,label}');
  end if;
  if coalesce((v_report_config#>>'{fields,findings,required}')::boolean, false) and v_old.findings is null then
    v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,findings,label}');
  end if;
  if coalesce((v_report_config#>>'{fields,conclusion,required}')::boolean, false) and v_old.conclusion is null then
    v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,conclusion,label}');
  end if;
  if coalesce((v_report_config#>>'{fields,observations,required}')::boolean, false)
     and nullif(btrim(v_old.result_data->>'notes'), '') is null then
    v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,observations,label}');
  end if;
  if cardinality(v_missing_report) > 0 then
    raise exception 'Preencha os campos obrigatórios do laudo: %.', array_to_string(v_missing_report, ', ');
  end if;

  if v_old.result_data->>'schema' = 'hpsm.lab_result.v1' then
    select string_agg(snapshot->>'label', ', ' order by (snapshot->>'sort_order')::integer) into v_missing
    from jsonb_array_elements(v_old.result_data#>'{template_snapshot,parameters}') snapshot
    where (snapshot->>'active')::boolean and (snapshot->>'required')::boolean
      and not exists (
        select 1 from jsonb_array_elements(v_old.result_data->'parameters') result_parameter
        where result_parameter->>'key' = snapshot->>'key' and nullif(btrim(result_parameter->>'value'), '') is not null
      );
    if v_missing is not null then raise exception 'Preencha os parâmetros obrigatórios: %.', v_missing; end if;
  elsif v_old.result_data->>'schema' = 'hpsm.image_result.v1' then
    if (v_old.result_data#>>'{template_snapshot,region,required}')::boolean and nullif(btrim(v_old.result_data->>'region'), '') is null then
      raise exception 'Selecione a região examinada.';
    end if;
    if v_old.result_data->>'region' = 'Outra região' and nullif(btrim(v_old.result_data->>'other_region'), '') is null then
      raise exception 'Informe a outra região examinada.';
    end if;
    if (v_old.result_data#>>'{template_snapshot,supports_laterality}')::boolean and nullif(v_old.result_data->>'laterality', '') is null then
      raise exception 'Selecione a lateralidade.';
    end if;
    if (v_old.result_data#>>'{template_snapshot,supports_contrast}')::boolean and nullif(v_old.result_data->>'contrast', '') is null then
      raise exception 'Informe o uso de contraste.';
    end if;
    if (v_old.result_data#>>'{template_snapshot,requires_image}')::boolean and not exists (
      select 1 from public.clinical_exam_images image where image.exam_id = p_exam_id and image.removed_at is null
    ) then raise exception 'Adicione ao menos uma imagem antes do envio.'; end if;
  end if;

  v_note := case when exists (
    select 1 from public.clinical_exam_status_history history
    where history.exam_id = p_exam_id and history.to_status = 'awaiting_review'
  ) then 'Exame corrigido e reenviado para revisão.' else 'Exame enviado para revisão.' end;

  update public.clinical_exams
  set status = 'awaiting_review', submitted_for_review_at = now(), correction_reason = null
  where id = p_exam_id
  returning * into v_new;

  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (p_exam_id, 'in_progress', 'awaiting_review', v_actor, v_note);

  select coalesce(max(version.version_number), 0) + 1
  into v_version
  from public.clinical_exam_report_versions version
  where version.exam_id = p_exam_id;

  insert into public.clinical_exam_report_versions (
    exam_id, version_number, snapshot, submitted_by, submitted_at
  ) values (
    p_exam_id, v_version, private.build_clinical_exam_report_snapshot(p_exam_id), v_actor, v_new.submitted_for_review_at
  );

  perform private.audit_exam_action(v_actor, 'clinical_exam.submitted_for_review', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
end;
$function$;

CREATE OR REPLACE FUNCTION public.submit_hr_hour_justification(p_weekly_record_id bigint, p_reason text, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_week public.rh_weekly_records;
  v_row public.rh_hour_justifications;
begin
  select * into v_week
  from public.rh_weekly_records
  where id = p_weekly_record_id
  for update;

  if not found or v_week.employee_id <> p_actor_id then
    raise exception using errcode = '42501', message = 'Pendência de horas indisponível para este colaborador.';
  end if;
  if v_week.closure_status <> 'awaiting_justification' or v_week.remaining_deficit_minutes <= 0 then
    raise exception using errcode = 'P0001', message = 'Esta semana não está aguardando justificativa.';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe o motivo entre 10 e 2000 caracteres.';
  end if;

  insert into public.rh_hour_justifications (
    weekly_record_id, employee_id, deficit_minutes, reason
  ) values (
    v_week.id, v_week.employee_id, v_week.remaining_deficit_minutes, btrim(p_reason)
  ) returning * into v_row;

  update public.rh_weekly_records
  set closure_status = 'justification_pending', updated_at = now()
  where id = v_week.id;

  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.unlink_patient_partnership(p_membership_id bigint, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_membership public.patient_partnerships%rowtype;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if char_length(v_reason) not between 2 and 500 then raise exception 'Informe o motivo da remoção.' using errcode = '22023'; end if;
  select * into v_membership from public.patient_partnerships where id = p_membership_id for update;
  if not found or v_membership.status <> 'active' then raise exception 'Vínculo ativo não localizado.' using errcode = '22023'; end if;
  update public.patient_partnerships set status = 'inactive', unlinked_at = now(),
    unlinked_by_type = 'professional', unlinked_by_user_id = v_actor, unlink_reason = v_reason
  where id = p_membership_id;
  perform private.partnership_audit('PARTNERSHIP_MEMBER_REMOVED', 'patient_partnerships', p_membership_id::text,
    'professional', v_actor, null, null,
    jsonb_build_object('partnership_id', v_membership.partnership_id, 'patient_id', v_membership.patient_id, 'reason', v_reason));
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.unlock_professional_identity_reprocess(p_target_user_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_actor_passport text;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if not private.hpsm_identity_is_director_general(v_actor) then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;
  if v_reason is null or char_length(v_reason) not between 5 and 500 then
    raise exception 'Informe o motivo do reprocessamento.' using errcode = '22023';
  end if;
  update public.professional_identities
  set identity_locked = false,
      signature_regeneration_reason = v_reason,
      last_failure_code = null,
      updated_at = now()
  where user_id = p_target_user_id;
  if not found then raise exception 'Identidade profissional nao localizada.' using errcode = 'P0002'; end if;
  select passport into v_actor_passport from public.profiles where user_id = v_actor;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (v_actor, v_actor_passport, 'IDENTITY_UNLOCKED', 'professional_identities', p_target_user_id::text,
    jsonb_build_object('identity_locked', true), jsonb_build_object('identity_locked', false, 'reason', v_reason));
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_catalog_pricing(p_service_id bigint, p_unit_price numeric, p_discounts jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_count integer;
begin
  if not private.has_permission((select auth.uid()), 'catalog.manage') then
    raise exception 'Você não possui permissão para alterar preços e descontos.';
  end if;
  if p_service_id is null or round(coalesce(p_unit_price, -1), 2) < 0 then
    raise exception 'Valor inválido.';
  end if;
  if p_discounts is null or jsonb_typeof(p_discounts) <> 'array' then
    raise exception 'Informe os descontos dos três planos.';
  end if;
  select count(*) into v_count
  from jsonb_to_recordset(p_discounts) as item(plan_code text, discount_percent numeric)
  join public.benefit_plans plan on plan.code = item.plan_code
  where item.discount_percent between 0 and 100;
  if v_count <> 3 or jsonb_array_length(p_discounts) <> 3 or exists (
    select 1 from jsonb_to_recordset(p_discounts) as item(plan_code text, discount_percent numeric)
    group by item.plan_code having count(*) <> 1
  ) then
    raise exception 'Os descontos dos três planos devem ser válidos e únicos.';
  end if;
  update public.service_catalog
  set unit_price = round(p_unit_price, 2), updated_by = (select auth.uid())
  where id = p_service_id;
  if not found then raise exception 'Item não localizado.'; end if;
  update public.plan_discounts discount
  set discount_percent = round(input.discount_percent, 2), updated_by = (select auth.uid())
  from jsonb_to_recordset(p_discounts) as input(plan_code text, discount_percent numeric)
  where discount.service_id = p_service_id and discount.plan_code = input.plan_code;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_clinical_cast_expected_removal(p_cast_id bigint, p_expected_removal_at timestamp with time zone, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid;
  v_old public.clinical_casts;
  v_new public.clinical_casts;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  v_actor := private.hpsm_current_actor();
  select * into v_old from public.clinical_casts where id = p_cast_id for update;
  if v_old.id is null then raise exception 'Registro de gesso não localizado.'; end if;
  if v_actor is null or not (
    private.has_permission(v_actor, 'casts.manage')
    or (v_old.applied_by = v_actor and private.has_permission(v_actor, 'casts.create'))
  ) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_old.status <> 'in_use' then raise exception 'Somente gessos em uso permitem alterar a previsão.'; end if;
  if p_expected_removal_at is null or p_expected_removal_at <= v_old.applied_at then
    raise exception 'A previsão de retirada deve ser posterior à aplicação.';
  end if;
  if p_expected_removal_at = v_old.expected_removal_at then raise exception 'Informe uma nova previsão de retirada.'; end if;
  if char_length(v_reason) not between 2 and 500 then raise exception 'Informe o motivo da alteração.'; end if;

  update public.clinical_casts
  set expected_removal_at = p_expected_removal_at
  where id = p_cast_id
  returning * into v_new;

  perform private.audit_cast_action(
    v_actor, 'CAST_EXPECTED_REMOVAL_CHANGED', v_new.id,
    jsonb_build_object('expected_removal_at', v_old.expected_removal_at),
    jsonb_build_object('expected_removal_at', v_new.expected_removal_at, 'reason', v_reason)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_course(p_course_id bigint, p_name text, p_description text, p_active boolean, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row public.courses;
begin
  if not private.has_permission(p_actor_id, 'courses.manage')
     or coalesce(private.current_position_level(p_actor_id), 0) < 11 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para alterar cursos.';
  end if;
  update public.courses
  set name = btrim(p_name), description = btrim(coalesce(p_description, '')),
      active = p_active, updated_by = p_actor_id, updated_at = now()
  where id = p_course_id returning * into v_row;
  if not found then raise exception using errcode = 'P0002', message = 'Curso não encontrado.'; end if;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_partnership(p_partnership_id bigint, p_name text, p_notes text DEFAULT NULL::text, p_responsible_patient_id bigint DEFAULT NULL::bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_current public.partnerships%rowtype;
  v_name text := btrim(coalesce(p_name, ''));
  v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
begin
  select * into v_current from public.partnerships where id = p_partnership_id for update;
  if not found then raise exception 'Parceria não localizada.' using errcode = '22023'; end if;
  if char_length(v_name) not between 2 and 120 then raise exception 'Informe o nome da parceria.' using errcode = '22023'; end if;
  if v_notes is not null and char_length(v_notes) > 2000 then raise exception 'A observação pode ter até 2.000 caracteres.' using errcode = '22023'; end if;
  if p_responsible_patient_id is not null and not private.partnership_patient_can_use_portal(p_responsible_patient_id) then
    raise exception 'O responsável precisa ser um paciente cadastrado com data de nascimento válida para acessar o Portal.' using errcode = '22023';
  end if;

  update public.partnerships set
    name = v_name,
    notes = v_notes,
    responsible_patient_id = p_responsible_patient_id,
    responsible_assigned_at = case
      when responsible_patient_id is distinct from p_responsible_patient_id and p_responsible_patient_id is not null then now()
      when p_responsible_patient_id is null then null
      else responsible_assigned_at end,
    responsible_assigned_by = case
      when responsible_patient_id is distinct from p_responsible_patient_id and p_responsible_patient_id is not null then v_actor
      when p_responsible_patient_id is null then null
      else responsible_assigned_by end,
    updated_at = now(),
    updated_by = v_actor
  where id = p_partnership_id;

  if v_current.responsible_patient_id is distinct from p_responsible_patient_id then
    insert into public.partnership_responsible_history (partnership_id, previous_patient_id, responsible_patient_id, changed_by)
    values (p_partnership_id, v_current.responsible_patient_id, p_responsible_patient_id, v_actor);
  end if;
  perform private.partnership_audit('PARTNERSHIP_UPDATED', 'partnerships', p_partnership_id::text, 'professional', v_actor, null,
    jsonb_build_object('name', v_current.name, 'responsible_patient_id', v_current.responsible_patient_id),
    jsonb_build_object('name', v_name, 'responsible_patient_id', p_responsible_patient_id));
  return true;
exception when unique_violation then
  raise exception 'Já existe uma parceria com este nome.' using errcode = '23505';
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_staff_position(p_position_id bigint, p_name text, p_active boolean, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_current public.staff_positions;
  v_row public.staff_positions;
begin
  if not private.has_permission(p_actor_id, 'access.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para alterar cargos.';
  end if;
  select * into v_current from public.staff_positions where id = p_position_id;
  if not found then raise exception using errcode = 'P0002', message = 'Cargo não encontrado.'; end if;
  if v_current.official and (btrim(p_name) <> v_current.name or p_active is not true) then
    raise exception using errcode = '42501', message = 'Os 14 cargos oficiais não podem ser renomeados ou inativados.';
  end if;
  update public.staff_positions
  set name = btrim(p_name), active = p_active, updated_by = p_actor_id, updated_at = now()
  where id = p_position_id returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

-- Índices não pertencentes a constraints.
CREATE INDEX attendance_items_attendance_id_idx ON public.attendance_items USING btree (attendance_id);
CREATE INDEX attendance_items_service_id_idx ON public.attendance_items USING btree (service_id);
CREATE INDEX attendances_cancelled_by_idx ON public.attendances USING btree (cancelled_by) WHERE (cancelled_by IS NOT NULL);
CREATE INDEX attendances_created_at_idx ON public.attendances USING btree (created_at DESC);
CREATE INDEX attendances_partnership_completed_idx ON public.attendances USING btree (partnership_id, created_at DESC, id DESC) WHERE ((status = 'completed'::text) AND (partnership_id IS NOT NULL));
CREATE INDEX attendances_patient_completed_created_idx ON public.attendances USING btree (patient_id, created_at DESC, id DESC) WHERE (status = 'completed'::text);
CREATE INDEX attendances_patient_created_idx ON public.attendances USING btree (patient_id, created_at DESC);
CREATE INDEX attendances_performed_by_created_idx ON public.attendances USING btree (performed_by, created_at DESC);
CREATE INDEX attendances_status_created_idx ON public.attendances USING btree (status, created_at DESC);
CREATE INDEX audit_logs_actor_user_id_idx ON public.audit_logs USING btree (actor_user_id) WHERE (actor_user_id IS NOT NULL);
CREATE INDEX audit_logs_clinical_cast_forecast_idx ON public.audit_logs USING btree (entity_id, created_at DESC) WHERE ((entity_name = 'clinical_casts'::text) AND (action = 'CAST_EXPECTED_REMOVAL_CHANGED'::text));
CREATE INDEX audit_logs_created_at_idx ON public.audit_logs USING btree (created_at DESC);
CREATE INDEX clinical_casts_active_duplicate_idx ON public.clinical_casts USING btree (patient_id, body_region, laterality) WHERE (status = 'in_use'::text);
CREATE INDEX clinical_casts_applied_by_idx ON public.clinical_casts USING btree (applied_by, applied_at DESC);
CREATE INDEX clinical_casts_attendance_idx ON public.clinical_casts USING btree (attendance_id) WHERE (attendance_id IS NOT NULL);
CREATE INDEX clinical_casts_cancelled_by_idx ON public.clinical_casts USING btree (cancelled_by, cancelled_at DESC) WHERE (cancelled_by IS NOT NULL);
CREATE INDEX clinical_casts_created_by_idx ON public.clinical_casts USING btree (created_by, created_at DESC);
CREATE INDEX clinical_casts_in_use_due_idx ON public.clinical_casts USING btree (expected_removal_at, id) WHERE (status = 'in_use'::text);
CREATE INDEX clinical_casts_patient_in_use_due_idx ON public.clinical_casts USING btree (patient_id, expected_removal_at, id) WHERE (status = 'in_use'::text);
CREATE INDEX clinical_casts_patient_updated_idx ON public.clinical_casts USING btree (patient_id, updated_at DESC, id DESC);
CREATE INDEX clinical_casts_removed_by_idx ON public.clinical_casts USING btree (removed_by, removed_at DESC) WHERE (removed_by IS NOT NULL);
CREATE INDEX clinical_casts_status_updated_idx ON public.clinical_casts USING btree (status, updated_at DESC, id DESC);
CREATE INDEX clinical_exam_document_shares_created_by_idx ON public.clinical_exam_document_shares USING btree (created_by);
CREATE INDEX clinical_exam_document_shares_created_by_patient_idx ON public.clinical_exam_document_shares USING btree (created_by_patient_id) WHERE (created_by_patient_id IS NOT NULL);
CREATE INDEX clinical_exam_document_shares_document_idx ON public.clinical_exam_document_shares USING btree (document_id);
CREATE INDEX clinical_exam_document_shares_exam_history_idx ON public.clinical_exam_document_shares USING btree (exam_id, created_at DESC);
CREATE UNIQUE INDEX clinical_exam_document_shares_one_active_uidx ON public.clinical_exam_document_shares USING btree (exam_id) WHERE (revoked_at IS NULL);
CREATE INDEX clinical_exam_document_shares_revoked_by_idx ON public.clinical_exam_document_shares USING btree (revoked_by) WHERE (revoked_by IS NOT NULL);
CREATE INDEX clinical_exam_documents_created_by_idx ON public.clinical_exam_documents USING btree (created_by);
CREATE INDEX clinical_exam_documents_created_by_patient_idx ON public.clinical_exam_documents USING btree (created_by_patient_id) WHERE (created_by_patient_id IS NOT NULL);
CREATE UNIQUE INDEX clinical_exam_documents_exam_render_version_uidx ON public.clinical_exam_documents USING btree (exam_id, render_version);
CREATE INDEX clinical_exam_images_exam_active_idx ON public.clinical_exam_images USING btree (exam_id, sort_order, created_at, id) WHERE (removed_at IS NULL);
CREATE INDEX clinical_exam_images_removed_by_idx ON public.clinical_exam_images USING btree (removed_by, removed_at DESC) WHERE (removed_by IS NOT NULL);
CREATE INDEX clinical_exam_images_uploaded_by_idx ON public.clinical_exam_images USING btree (uploaded_by, created_at DESC);
CREATE INDEX clinical_exam_report_versions_exam_date_idx ON public.clinical_exam_report_versions USING btree (exam_id, submitted_at DESC, id DESC);
CREATE INDEX clinical_exam_report_versions_pending_idx ON public.clinical_exam_report_versions USING btree (exam_id, version_number DESC) WHERE (decision = 'pending'::text);
CREATE INDEX clinical_exam_report_versions_reviewed_by_idx ON public.clinical_exam_report_versions USING btree (reviewed_by, reviewed_at DESC) WHERE (reviewed_by IS NOT NULL);
CREATE INDEX clinical_exam_report_versions_submitted_by_idx ON public.clinical_exam_report_versions USING btree (submitted_by, submitted_at DESC);
CREATE INDEX clinical_exam_history_changed_by_idx ON public.clinical_exam_status_history USING btree (changed_by, changed_at DESC);
CREATE INDEX clinical_exam_history_exam_date_idx ON public.clinical_exam_status_history USING btree (exam_id, changed_at, id);
CREATE INDEX clinical_exams_attendance_idx ON public.clinical_exams USING btree (attendance_id) WHERE (attendance_id IS NOT NULL);
CREATE INDEX clinical_exams_patient_completed_at_idx ON public.clinical_exams USING btree (patient_id, completed_at DESC, id DESC) WHERE ((status = 'completed'::text) AND (completed_at IS NOT NULL));
CREATE INDEX clinical_exams_patient_requested_idx ON public.clinical_exams USING btree (patient_id, requested_at DESC, id DESC);
CREATE INDEX clinical_exams_patient_status_requested_idx ON public.clinical_exams USING btree (patient_id, status, requested_at DESC, id DESC);
CREATE INDEX clinical_exams_requested_at_idx ON public.clinical_exams USING btree (requested_at DESC, id DESC);
CREATE INDEX clinical_exams_requested_by_idx ON public.clinical_exams USING btree (requested_by, requested_at DESC);
CREATE INDEX clinical_exams_responsible_status_idx ON public.clinical_exams USING btree (responsible_professional_id, status, requested_at DESC);
CREATE INDEX clinical_exams_reviewed_by_idx ON public.clinical_exams USING btree (reviewed_by, completed_at DESC) WHERE (reviewed_by IS NOT NULL);
CREATE INDEX clinical_exams_status_requested_idx ON public.clinical_exams USING btree (status, requested_at DESC, id DESC);
CREATE INDEX clinical_exams_type_requested_idx ON public.clinical_exams USING btree (exam_type_id, requested_at DESC, id DESC);
CREATE INDEX courses_active_name_idx ON public.courses USING btree (active, name);
CREATE INDEX courses_created_by_idx ON public.courses USING btree (created_by);
CREATE UNIQUE INDEX courses_name_unique_idx ON public.courses USING btree (lower(btrim(name)));
CREATE INDEX courses_updated_by_idx ON public.courses USING btree (updated_by);
CREATE INDEX exam_ai_generations_exam_latest_idx ON public.exam_ai_generations USING btree (exam_id, generation_type, created_at DESC, id DESC);
CREATE INDEX exam_ai_generations_official_image_id_idx ON public.exam_ai_generations USING btree (official_image_id) WHERE (official_image_id IS NOT NULL);
CREATE UNIQUE INDEX exam_ai_generations_one_active_idx ON public.exam_ai_generations USING btree (exam_id, generation_type) WHERE (status = 'requested'::text);
CREATE INDEX exam_ai_generations_requested_by_idx ON public.exam_ai_generations USING btree (requested_by, created_at DESC);
CREATE INDEX exam_ai_generations_source_image_generation_idx ON public.exam_ai_generations USING btree (source_image_generation_id) WHERE (source_image_generation_id IS NOT NULL);
CREATE INDEX exam_ai_generations_source_image_id_idx ON public.exam_ai_generations USING btree (source_image_id) WHERE (source_image_id IS NOT NULL);
CREATE INDEX exam_categories_active_sort_idx ON public.exam_categories USING btree (active, sort_order, name);
CREATE INDEX exam_categories_created_by_idx ON public.exam_categories USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE UNIQUE INDEX exam_categories_name_unique_idx ON public.exam_categories USING btree (lower(name));
CREATE INDEX exam_categories_updated_by_idx ON public.exam_categories USING btree (updated_by) WHERE (updated_by IS NOT NULL);
CREATE INDEX exam_types_category_active_sort_idx ON public.exam_types USING btree (category_id, active, sort_order, name);
CREATE UNIQUE INDEX exam_types_category_name_unique_idx ON public.exam_types USING btree (category_id, lower(name));
CREATE INDEX exam_types_created_by_idx ON public.exam_types USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE INDEX exam_types_updated_by_idx ON public.exam_types USING btree (updated_by) WHERE (updated_by IS NOT NULL);
CREATE INDEX notification_reads_user_idx ON public.notification_reads USING btree (user_id, read_at DESC);
CREATE INDEX notifications_archived_by_idx ON public.notifications USING btree (archived_by) WHERE (archived_by IS NOT NULL);
CREATE INDEX notifications_audience_active_idx ON public.notifications USING btree (audience, created_at DESC) WHERE ((audience IS NOT NULL) AND (archived_at IS NULL));
CREATE INDEX notifications_created_by_idx ON public.notifications USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE INDEX notifications_open_source_idx ON public.notifications USING btree (source_type, source_id, created_at DESC) WHERE ((source_type IS NOT NULL) AND (resolved_at IS NULL) AND (archived_at IS NULL));
CREATE INDEX notifications_recipient_active_idx ON public.notifications USING btree (recipient_id, created_at DESC) WHERE ((recipient_id IS NOT NULL) AND (archived_at IS NULL));
CREATE INDEX notifications_required_permission_idx ON public.notifications USING btree (required_permission, created_at DESC) WHERE ((required_permission IS NOT NULL) AND (archived_at IS NULL));
CREATE INDEX notifications_resolved_by_idx ON public.notifications USING btree (resolved_by) WHERE (resolved_by IS NOT NULL);
CREATE INDEX partnership_pending_canceled_by_patient_idx ON public.partnership_pending_beneficiaries USING btree (canceled_by_patient_id) WHERE (canceled_by_patient_id IS NOT NULL);
CREATE INDEX partnership_pending_canceled_by_user_idx ON public.partnership_pending_beneficiaries USING btree (canceled_by_user_id) WHERE (canceled_by_user_id IS NOT NULL);
CREATE INDEX partnership_pending_created_by_patient_idx ON public.partnership_pending_beneficiaries USING btree (created_by_patient_id) WHERE (created_by_patient_id IS NOT NULL);
CREATE INDEX partnership_pending_created_by_user_idx ON public.partnership_pending_beneficiaries USING btree (created_by_user_id) WHERE (created_by_user_id IS NOT NULL);
CREATE UNIQUE INDEX partnership_pending_open_unique_idx ON public.partnership_pending_beneficiaries USING btree (partnership_id, passport) WHERE (status = ANY (ARRAY['pending_registration'::text, 'name_review'::text]));
CREATE INDEX partnership_pending_partnership_status_idx ON public.partnership_pending_beneficiaries USING btree (partnership_id, status, created_at DESC, id DESC);
CREATE INDEX partnership_pending_passport_status_idx ON public.partnership_pending_beneficiaries USING btree (passport, status, partnership_id);
CREATE INDEX partnership_pending_resolved_patient_idx ON public.partnership_pending_beneficiaries USING btree (resolved_patient_id) WHERE (resolved_patient_id IS NOT NULL);
CREATE INDEX partnership_responsible_history_changed_by_idx ON public.partnership_responsible_history USING btree (changed_by);
CREATE INDEX partnership_responsible_history_partnership_idx ON public.partnership_responsible_history USING btree (partnership_id, changed_at DESC, id DESC);
CREATE INDEX partnership_responsible_history_previous_patient_idx ON public.partnership_responsible_history USING btree (previous_patient_id) WHERE (previous_patient_id IS NOT NULL);
CREATE INDEX partnership_responsible_history_responsible_patient_idx ON public.partnership_responsible_history USING btree (responsible_patient_id) WHERE (responsible_patient_id IS NOT NULL);
CREATE INDEX partnership_status_history_changed_by_idx ON public.partnership_status_history USING btree (changed_by);
CREATE INDEX partnership_status_history_partnership_idx ON public.partnership_status_history USING btree (partnership_id, changed_at DESC, id DESC);
CREATE INDEX partnerships_created_by_idx ON public.partnerships USING btree (created_by);
CREATE INDEX partnerships_deactivated_by_idx ON public.partnerships USING btree (deactivated_by) WHERE (deactivated_by IS NOT NULL);
CREATE UNIQUE INDEX partnerships_name_unique_idx ON public.partnerships USING btree (lower(btrim(name)));
CREATE INDEX partnerships_responsible_assigned_by_idx ON public.partnerships USING btree (responsible_assigned_by) WHERE (responsible_assigned_by IS NOT NULL);
CREATE INDEX partnerships_responsible_idx ON public.partnerships USING btree (responsible_patient_id, status, id) WHERE (responsible_patient_id IS NOT NULL);
CREATE INDEX partnerships_status_name_idx ON public.partnerships USING btree (status, lower(name), id);
CREATE INDEX partnerships_updated_by_idx ON public.partnerships USING btree (updated_by);
CREATE INDEX patient_health_plan_requests_patient_approved_idx ON public.patient_health_plan_requests USING btree (patient_id, coverage_end DESC) WHERE (status = 'approved'::text);
CREATE INDEX patient_health_plan_requests_patient_requested_idx ON public.patient_health_plan_requests USING btree (patient_id, requested_at DESC, id DESC);
CREATE INDEX patient_health_plan_requests_pending_idx ON public.patient_health_plan_requests USING btree (requested_at, id) WHERE (status = 'pending'::text);
CREATE INDEX patient_health_plan_requests_reviewed_by_idx ON public.patient_health_plan_requests USING btree (reviewed_by) WHERE (reviewed_by IS NOT NULL);
CREATE UNIQUE INDEX patient_partnerships_active_unique_idx ON public.patient_partnerships USING btree (partnership_id, patient_id) WHERE (status = 'active'::text);
CREATE INDEX patient_partnerships_linked_by_patient_idx ON public.patient_partnerships USING btree (linked_by_patient_id) WHERE (linked_by_patient_id IS NOT NULL);
CREATE INDEX patient_partnerships_linked_by_user_idx ON public.patient_partnerships USING btree (linked_by_user_id) WHERE (linked_by_user_id IS NOT NULL);
CREATE INDEX patient_partnerships_partnership_status_idx ON public.patient_partnerships USING btree (partnership_id, status, linked_at DESC, id DESC);
CREATE INDEX patient_partnerships_patient_status_idx ON public.patient_partnerships USING btree (patient_id, status, partnership_id);
CREATE INDEX patient_partnerships_unlinked_by_patient_idx ON public.patient_partnerships USING btree (unlinked_by_patient_id) WHERE (unlinked_by_patient_id IS NOT NULL);
CREATE INDEX patient_partnerships_unlinked_by_user_idx ON public.patient_partnerships USING btree (unlinked_by_user_id) WHERE (unlinked_by_user_id IS NOT NULL);
CREATE INDEX patient_portal_attempts_cleanup_idx ON public.patient_portal_login_attempts USING btree (attempted_at);
CREATE INDEX patient_portal_attempts_origin_failed_idx ON public.patient_portal_login_attempts USING btree (origin_hash, attempted_at DESC) WHERE ((NOT succeeded) AND (NOT blocked));
CREATE INDEX patient_portal_attempts_passport_failed_idx ON public.patient_portal_login_attempts USING btree (passport_hash, attempted_at DESC) WHERE ((NOT succeeded) AND (NOT blocked));
CREATE INDEX patient_portal_attempts_patient_idx ON public.patient_portal_login_attempts USING btree (patient_id, attempted_at DESC) WHERE (patient_id IS NOT NULL);
CREATE INDEX patient_portal_sessions_expires_idx ON public.patient_portal_sessions USING btree (expires_at) WHERE (revoked_at IS NULL);
CREATE INDEX patient_portal_sessions_patient_idx ON public.patient_portal_sessions USING btree (patient_id, created_at DESC);
CREATE UNIQUE INDEX patient_portal_sessions_token_hash_idx ON public.patient_portal_sessions USING btree (token_hash);
CREATE INDEX patients_created_by_idx ON public.patients USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE INDEX patients_name_trgm_idx ON public.patients USING gin (name gin_trgm_ops);
CREATE INDEX patients_passport_prefix_idx ON public.patients USING btree (passport text_pattern_ops);
CREATE UNIQUE INDEX patients_passport_unique_idx ON public.patients USING btree (passport);
CREATE INDEX patients_plan_code_idx ON public.patients USING btree (plan_code) WHERE (plan_code IS NOT NULL);
CREATE INDEX patients_updated_by_idx ON public.patients USING btree (updated_by) WHERE (updated_by IS NOT NULL);
CREATE INDEX plan_discounts_service_id_idx ON public.plan_discounts USING btree (service_id);
CREATE INDEX plan_discounts_updated_by_idx ON public.plan_discounts USING btree (updated_by) WHERE (updated_by IS NOT NULL);
CREATE INDEX professional_identities_generated_by_idx ON public.professional_identities USING btree (signature_generated_by) WHERE (signature_generated_by IS NOT NULL);
CREATE INDEX professional_identities_regenerated_by_idx ON public.professional_identities USING btree (signature_regenerated_by) WHERE (signature_regenerated_by IS NOT NULL);
CREATE INDEX professional_identities_status_idx ON public.professional_identities USING btree (status, updated_at DESC);
CREATE INDEX profiles_created_by_idx ON public.profiles USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE INDEX profiles_password_reset_by_idx ON public.profiles USING btree (password_reset_by) WHERE (password_reset_by IS NOT NULL);
CREATE INDEX profiles_position_idx ON public.profiles USING btree (position_id) WHERE (position_id IS NOT NULL);
CREATE UNIQUE INDEX profiles_single_general_director ON public.profiles USING btree (role_code) WHERE (role_code = 'diretor_geral'::text);
CREATE INDEX profiles_updated_by_idx ON public.profiles USING btree (updated_by) WHERE (updated_by IS NOT NULL);
CREATE INDEX recruitment_created_at_idx ON public.recruitment_applications USING btree (created_at DESC);
CREATE INDEX recruitment_reviewed_by_idx ON public.recruitment_applications USING btree (reviewed_by) WHERE (reviewed_by IS NOT NULL);
CREATE INDEX recruitment_status_created_idx ON public.recruitment_applications USING btree (status, created_at DESC);
CREATE INDEX recruitment_decisions_application_idx ON public.recruitment_decisions USING btree (application_id, decided_at DESC);
CREATE INDEX recruitment_decisions_decided_by_idx ON public.recruitment_decisions USING btree (decided_by);
CREATE INDEX rh_absence_requests_cancelled_by_idx ON public.rh_absence_requests USING btree (cancelled_by) WHERE (cancelled_by IS NOT NULL);
CREATE INDEX rh_absence_requests_employee_period_idx ON public.rh_absence_requests USING btree (employee_id, start_date DESC, end_date DESC);
CREATE INDEX rh_absence_requests_pending_idx ON public.rh_absence_requests USING btree (requested_at) WHERE (status = 'pending'::text);
CREATE INDEX rh_absence_requests_reviewed_by_idx ON public.rh_absence_requests USING btree (reviewed_by) WHERE (reviewed_by IS NOT NULL);
CREATE INDEX rh_disciplinary_reviews_decided_by_idx ON public.rh_disciplinary_reviews USING btree (decided_by) WHERE (decided_by IS NOT NULL);
CREATE INDEX rh_disciplinary_reviews_employee_cycle_idx ON public.rh_disciplinary_reviews USING btree (employee_id, cycle_month, triggered_at DESC);
CREATE INDEX rh_disciplinary_reviews_pending_idx ON public.rh_disciplinary_reviews USING btree (triggered_at) WHERE (status = 'pending'::text);
CREATE INDEX rh_disciplinary_reviews_triggered_by_idx ON public.rh_disciplinary_reviews USING btree (triggered_by);
CREATE INDEX rh_hour_justifications_employee_idx ON public.rh_hour_justifications USING btree (employee_id, submitted_at DESC);
CREATE INDEX rh_hour_justifications_pending_idx ON public.rh_hour_justifications USING btree (submitted_at) WHERE (status = 'pending'::text);
CREATE INDEX rh_hour_justifications_reviewed_by_idx ON public.rh_hour_justifications USING btree (reviewed_by) WHERE (reviewed_by IS NOT NULL);
CREATE INDEX rh_hour_snapshots_created_by_idx ON public.rh_hour_snapshots USING btree (created_by);
CREATE INDEX rh_hour_snapshots_employee_date_idx ON public.rh_hour_snapshots USING btree (employee_id, reading_date DESC);
CREATE INDEX rh_hour_snapshots_updated_by_idx ON public.rh_hour_snapshots USING btree (updated_by);
CREATE INDEX rh_leave_week_adjustments_approved_by_idx ON public.rh_leave_week_adjustments USING btree (approved_by);
CREATE INDEX rh_leave_week_adjustments_employee_week_idx ON public.rh_leave_week_adjustments USING btree (employee_id, week_start);
CREATE INDEX rh_warnings_active_cycle_idx ON public.rh_warnings USING btree (cycle_month, employee_id) WHERE (status = 'active'::text);
CREATE INDEX rh_warnings_annulled_by_idx ON public.rh_warnings USING btree (annulled_by) WHERE (annulled_by IS NOT NULL);
CREATE INDEX rh_warnings_employee_cycle_idx ON public.rh_warnings USING btree (employee_id, cycle_month, issued_at DESC);
CREATE INDEX rh_warnings_issued_by_idx ON public.rh_warnings USING btree (issued_by);
CREATE INDEX rh_warnings_progression_flagged_by_idx ON public.rh_warnings USING btree (progression_flagged_by) WHERE (progression_flagged_by IS NOT NULL);
CREATE INDEX rh_warnings_progression_idx ON public.rh_warnings USING btree (employee_id, issued_at DESC) WHERE ((status = 'active'::text) AND impacts_progression);
CREATE INDEX rh_week_closures_closed_by_idx ON public.rh_week_closures USING btree (closed_by) WHERE (closed_by IS NOT NULL);
CREATE INDEX rh_week_closures_started_by_idx ON public.rh_week_closures USING btree (started_by);
CREATE INDEX rh_week_reopen_events_actor_idx ON public.rh_week_reopen_events USING btree (reopened_by);
CREATE INDEX rh_week_reopen_events_closure_idx ON public.rh_week_reopen_events USING btree (closure_id, reopened_at DESC);
CREATE INDEX rh_weekly_records_absence_request_idx ON public.rh_weekly_records USING btree (absence_request_id) WHERE (absence_request_id IS NOT NULL);
CREATE INDEX rh_weekly_records_closed_by_idx ON public.rh_weekly_records USING btree (closed_by);
CREATE INDEX rh_weekly_records_closure_idx ON public.rh_weekly_records USING btree (closure_id, closure_status);
CREATE INDEX rh_weekly_records_employee_cycle_idx ON public.rh_weekly_records USING btree (employee_id, cycle_month, week_start DESC);
CREATE INDEX rh_weekly_records_pending_justification_idx ON public.rh_weekly_records USING btree (employee_id, week_start) WHERE (closure_status = ANY (ARRAY['awaiting_justification'::text, 'justification_pending'::text]));
CREATE INDEX rh_weekly_records_status_cycle_idx ON public.rh_weekly_records USING btree (status, cycle_month);
CREATE INDEX service_catalog_active_sort_idx ON public.service_catalog USING btree (category, sort_order, name) WHERE (active = true);
CREATE INDEX service_catalog_created_by_idx ON public.service_catalog USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE UNIQUE INDEX service_catalog_name_unique_idx ON public.service_catalog USING btree (lower(btrim(name)));
CREATE INDEX service_catalog_updated_by_idx ON public.service_catalog USING btree (updated_by) WHERE (updated_by IS NOT NULL);
CREATE INDEX staff_course_records_assigned_by_idx ON public.staff_course_records USING btree (assigned_by);
CREATE INDEX staff_course_records_completed_by_idx ON public.staff_course_records USING btree (completed_by) WHERE (completed_by IS NOT NULL);
CREATE INDEX staff_course_records_employee_idx ON public.staff_course_records USING btree (employee_id, status, assigned_at DESC);
CREATE INDEX staff_position_history_decided_by_idx ON public.staff_position_history USING btree (decided_by, effective_at DESC);
CREATE INDEX staff_position_history_employee_idx ON public.staff_position_history USING btree (employee_id, effective_at DESC);
CREATE INDEX staff_position_history_from_position_idx ON public.staff_position_history USING btree (from_position_id) WHERE (from_position_id IS NOT NULL);
CREATE INDEX staff_position_history_to_position_idx ON public.staff_position_history USING btree (to_position_id);
CREATE INDEX staff_position_permissions_code_idx ON public.staff_position_permissions USING btree (permission_code, position_id);
CREATE INDEX staff_position_permissions_granted_by_idx ON public.staff_position_permissions USING btree (granted_by);
CREATE INDEX staff_position_transition_rules_to_position_idx ON public.staff_position_transition_rules USING btree (to_position_id);
CREATE INDEX staff_position_transition_rules_updated_by_idx ON public.staff_position_transition_rules USING btree (updated_by);
CREATE INDEX staff_positions_active_idx ON public.staff_positions USING btree (active, sort_order, name);
CREATE INDEX staff_positions_created_by_idx ON public.staff_positions USING btree (created_by);
CREATE UNIQUE INDEX staff_positions_level_unique_idx ON public.staff_positions USING btree (level) WHERE (level IS NOT NULL);
CREATE INDEX staff_positions_updated_by_idx ON public.staff_positions USING btree (updated_by);
CREATE INDEX staff_promotion_reviews_decided_by_idx ON public.staff_promotion_reviews USING btree (decided_by) WHERE (decided_by IS NOT NULL);
CREATE INDEX staff_promotion_reviews_from_position_idx ON public.staff_promotion_reviews USING btree (from_position_id);
CREATE UNIQUE INDEX staff_promotion_reviews_pending_employee_idx ON public.staff_promotion_reviews USING btree (employee_id) WHERE (status = 'pending'::text);
CREATE INDEX staff_promotion_reviews_status_idx ON public.staff_promotion_reviews USING btree (status, created_at DESC);
CREATE INDEX staff_promotion_reviews_to_position_idx ON public.staff_promotion_reviews USING btree (to_position_id);
CREATE INDEX user_permission_grants_granted_by_idx ON public.user_permission_grants USING btree (granted_by);
CREATE INDEX user_permission_grants_permission_active_idx ON public.user_permission_grants USING btree (permission_code, user_id, valid_from, expires_at) WHERE (revoked_at IS NULL);
CREATE INDEX user_permission_grants_revoked_by_idx ON public.user_permission_grants USING btree (revoked_by) WHERE (revoked_by IS NOT NULL);
CREATE INDEX user_permission_grants_user_active_idx ON public.user_permission_grants USING btree (user_id, permission_code, valid_from, expires_at) WHERE (revoked_at IS NULL);
CREATE INDEX user_permission_grants_user_history_idx ON public.user_permission_grants USING btree (user_id, granted_at DESC);

-- Policies RLS.
create policy "attendance_items_insert_own_authorized" on "public"."attendance_items" as permissive for insert to "authenticated" with check ((private.has_permission(( SELECT auth.uid() AS uid), 'attendances.create'::text) AND (EXISTS ( SELECT 1
   FROM attendances
  WHERE ((attendances.id = attendance_items.attendance_id) AND (attendances.performed_by = ( SELECT auth.uid() AS uid)) AND (attendances.status = 'completed'::text))))));
create policy "attendance_items_read_visible_attendance" on "public"."attendance_items" as permissive for select to "authenticated" using ((private.is_active_user() AND (EXISTS ( SELECT 1
   FROM attendances
  WHERE ((attendances.id = attendance_items.attendance_id) AND ((attendances.performed_by = ( SELECT auth.uid() AS uid)) OR private.has_permission(( SELECT auth.uid() AS uid), 'attendances.manage'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'patients.view'::text)))))));
create policy "phase10_valid_session" on "public"."attendance_items" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "attendances_cancel_authorized" on "public"."attendances" as permissive for update to "authenticated" using (private.has_permission(( SELECT auth.uid() AS uid), 'attendances.manage'::text)) with check ((private.has_permission(( SELECT auth.uid() AS uid), 'attendances.manage'::text) AND (status = 'cancelled'::text) AND (cancelled_by = ( SELECT auth.uid() AS uid)) AND (cancelled_at IS NOT NULL)));
create policy "attendances_insert_own_authorized" on "public"."attendances" as permissive for insert to "authenticated" with check ((private.has_permission(( SELECT auth.uid() AS uid), 'attendances.create'::text) AND (performed_by = ( SELECT auth.uid() AS uid)) AND (status = 'completed'::text) AND (cancelled_by IS NULL) AND (cancelled_at IS NULL)));
create policy "attendances_read_own_manage_or_patient_center" on "public"."attendances" as permissive for select to "authenticated" using ((private.is_active_user() AND ((performed_by = ( SELECT auth.uid() AS uid)) OR private.has_permission(( SELECT auth.uid() AS uid), 'attendances.manage'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'patients.view'::text))));
create policy "phase10_valid_session" on "public"."attendances" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "audit_read_directors" on "public"."audit_logs" as permissive for select to "authenticated" using (( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'audit.view'::text) AS is_director));
create policy "phase10_valid_session" on "public"."audit_logs" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "benefit_plans_read_authorized" on "public"."benefit_plans" as permissive for select to "authenticated" using ((private.has_permission(( SELECT auth.uid() AS uid), 'catalog.view'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'catalog.manage'::text)));
create policy "phase10_valid_session" on "public"."benefit_plans" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "clinical_casts_read_authorized" on "public"."clinical_casts" as permissive for select to "authenticated" using (( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'casts.view'::text) AS has_permission));
create policy "phase10_valid_session" on "public"."clinical_casts" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "phase10_valid_session" on "public"."clinical_exam_document_shares" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "phase10_valid_session" on "public"."clinical_exam_documents" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "clinical_exam_images_read_authorized" on "public"."clinical_exam_images" as permissive for select to "authenticated" using (( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'exams.view'::text) AS has_permission));
create policy "phase10_valid_session" on "public"."clinical_exam_images" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "clinical_exam_report_versions_read_authorized" on "public"."clinical_exam_report_versions" as permissive for select to "authenticated" using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND private.has_permission(( SELECT auth.uid() AS uid), 'exams.view'::text)));
create policy "phase10_valid_session" on "public"."clinical_exam_report_versions" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "clinical_exam_history_read_authorized" on "public"."clinical_exam_status_history" as permissive for select to "authenticated" using (( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'exams.view'::text) AS has_permission));
create policy "phase10_valid_session" on "public"."clinical_exam_status_history" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "clinical_exams_read_authorized" on "public"."clinical_exams" as permissive for select to "authenticated" using (( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'exams.view'::text) AS has_permission));
create policy "phase10_valid_session" on "public"."clinical_exams" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "courses_read_active_or_manager" on "public"."courses" as permissive for select to "authenticated" using ((active OR private.has_permission(( SELECT auth.uid() AS uid), 'courses.manage'::text)));
create policy "phase10_valid_session" on "public"."courses" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "dashboard_preferences_own_read" on "public"."dashboard_preferences" as permissive for select to "authenticated" using ((( SELECT auth.uid() AS uid) = user_id));
create policy "phase101_dashboard_valid_session" on "public"."dashboard_preferences" as restrictive for select to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "exam_ai_generations_read_participant" on "public"."exam_ai_generations" as permissive for select to "authenticated" using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM clinical_exams exam
  WHERE ((exam.id = exam_ai_generations.exam_id) AND (((exam.responsible_professional_id = ( SELECT auth.uid() AS uid)) AND private.has_permission(( SELECT auth.uid() AS uid), 'exams.perform'::text)) OR private.has_permission(( SELECT auth.uid() AS uid), 'exams.review'::text)))))));
create policy "phase10_valid_session" on "public"."exam_ai_generations" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "exam_categories_read_authorized" on "public"."exam_categories" as permissive for select to "authenticated" using ((( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'exams.view'::text) AS has_permission) OR ( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'exams.create'::text) AS has_permission) OR ( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'exams.perform'::text) AS has_permission) OR ( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'exams.review'::text) AS has_permission) OR ( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'exams.catalog.manage'::text) AS has_permission)));
create policy "phase10_valid_session" on "public"."exam_categories" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "exam_types_read_authorized" on "public"."exam_types" as permissive for select to "authenticated" using ((( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'exams.view'::text) AS has_permission) OR ( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'exams.create'::text) AS has_permission) OR ( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'exams.perform'::text) AS has_permission) OR ( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'exams.review'::text) AS has_permission) OR ( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'exams.catalog.manage'::text) AS has_permission)));
create policy "phase10_valid_session" on "public"."exam_types" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "notification_reads_read_own" on "public"."notification_reads" as permissive for select to "authenticated" using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)));
create policy "phase10_valid_session" on "public"."notification_reads" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "notifications_read_visible" on "public"."notifications" as permissive for select to "authenticated" using (private.can_view_notification(id, ( SELECT auth.uid() AS uid)));
create policy "phase10_valid_session" on "public"."notifications" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "catalog_images_delete_manager" on "storage"."objects" as permissive for delete to "authenticated" using (((bucket_id = 'catalog-images'::text) AND private.has_permission(( SELECT auth.uid() AS uid), 'catalog.manage'::text)));
create policy "catalog_images_insert_manager" on "storage"."objects" as permissive for insert to "authenticated" with check (((bucket_id = 'catalog-images'::text) AND private.has_permission(( SELECT auth.uid() AS uid), 'catalog.manage'::text)));
create policy "catalog_images_read_authorized" on "storage"."objects" as permissive for select to "authenticated" using (((bucket_id = 'catalog-images'::text) AND (private.has_permission(( SELECT auth.uid() AS uid), 'catalog.view'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'catalog.manage'::text))));
create policy "catalog_images_update_manager" on "storage"."objects" as permissive for update to "authenticated" using (((bucket_id = 'catalog-images'::text) AND private.has_permission(( SELECT auth.uid() AS uid), 'catalog.manage'::text))) with check (((bucket_id = 'catalog-images'::text) AND private.has_permission(( SELECT auth.uid() AS uid), 'catalog.manage'::text)));
create policy "clinical_exam_images_storage_delete" on "storage"."objects" as permissive for delete to "authenticated" using (((bucket_id = 'clinical-exam-images'::text) AND ((storage.foldername(name))[1] = 'clinical-exams'::text) AND (EXISTS ( SELECT 1
   FROM clinical_exams exam
  WHERE ((exam.id =
        CASE
            WHEN COALESCE(((storage.foldername(objects.name))[2] ~ '^[0-9]+$'::text), false) THEN ((storage.foldername(objects.name))[2])::bigint
            ELSE NULL::bigint
        END) AND (exam.status = 'in_progress'::text) AND (((exam.responsible_professional_id = ( SELECT auth.uid() AS uid)) AND private.has_permission(( SELECT auth.uid() AS uid), 'exams.perform'::text)) OR private.has_permission(( SELECT auth.uid() AS uid), 'exams.review'::text)))))));
create policy "clinical_exam_images_storage_read" on "storage"."objects" as permissive for select to "authenticated" using (((bucket_id = 'clinical-exam-images'::text) AND (EXISTS ( SELECT 1
   FROM clinical_exam_images image
  WHERE ((image.storage_path = objects.name) AND (image.removed_at IS NULL) AND private.has_permission(( SELECT auth.uid() AS uid), 'exams.view'::text))))));
create policy "phase10_hpsm_storage_session" on "storage"."objects" as restrictive for all to "authenticated" using (((bucket_id <> ALL (ARRAY['catalog-images'::text, 'clinical-exam-images'::text, 'clinical-exam-documents'::text])) OR ( SELECT private.hpsm_session_valid() AS hpsm_session_valid))) with check (((bucket_id <> ALL (ARRAY['catalog-images'::text, 'clinical-exam-images'::text, 'clinical-exam-documents'::text])) OR ( SELECT private.hpsm_session_valid() AS hpsm_session_valid)));
create policy "patient_health_plan_requests_read_patient_center" on "public"."patient_health_plan_requests" as permissive for select to "authenticated" using ((private.has_permission(( SELECT auth.uid() AS uid), 'healthplans.review'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'patients.view'::text)));
create policy "phase10_valid_session" on "public"."patient_health_plan_requests" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "phase10_valid_session" on "public"."patient_portal_login_attempts" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "phase10_valid_session" on "public"."patient_portal_sessions" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "patients_insert_authorized" on "public"."patients" as permissive for insert to "authenticated" with check ((private.has_permission(( SELECT auth.uid() AS uid), 'patients.view'::text) AND (created_by = ( SELECT auth.uid() AS uid)) AND (updated_by = ( SELECT auth.uid() AS uid))));
create policy "patients_read_authorized" on "public"."patients" as permissive for select to "authenticated" using (private.has_permission(( SELECT auth.uid() AS uid), 'patients.view'::text));
create policy "patients_update_authorized" on "public"."patients" as permissive for update to "authenticated" using (private.has_permission(( SELECT auth.uid() AS uid), 'patients.manage'::text)) with check ((private.has_permission(( SELECT auth.uid() AS uid), 'patients.manage'::text) AND (updated_by = ( SELECT auth.uid() AS uid))));
create policy "phase10_valid_session" on "public"."patients" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "phase10_valid_session" on "public"."plan_discounts" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "plan_discounts_read_authorized" on "public"."plan_discounts" as permissive for select to "authenticated" using ((private.has_permission(( SELECT auth.uid() AS uid), 'catalog.view'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'catalog.manage'::text)));
create policy "plan_discounts_update_authorized" on "public"."plan_discounts" as permissive for update to "authenticated" using (private.has_permission(( SELECT auth.uid() AS uid), 'catalog.manage'::text)) with check ((private.has_permission(( SELECT auth.uid() AS uid), 'catalog.manage'::text) AND (updated_by = ( SELECT auth.uid() AS uid))));
create policy "phase103_valid_session" on "public"."professional_identities" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "professional_identities_read_own_or_director" on "public"."professional_identities" as permissive for select to "authenticated" using (((user_id = ( SELECT auth.uid() AS uid)) OR private.hpsm_identity_is_director_general(( SELECT auth.uid() AS uid))));
create policy "phase10_valid_session" on "public"."profiles" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(false) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(false) AS hpsm_session_valid));
create policy "profiles_read_own_or_director" on "public"."profiles" as permissive for select to "authenticated" using (((user_id = ( SELECT auth.uid() AS uid)) OR ( SELECT (private.has_permission(( SELECT auth.uid() AS uid), 'team.manage'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'access.manage'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.team.view'::text)) AS is_director)));
create policy "phase10_valid_session" on "public"."recruitment_applications" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "recruitment_read_directors" on "public"."recruitment_applications" as permissive for select to "authenticated" using (( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'recruitment.manage'::text) AS has_permission));
create policy "recruitment_update_directors" on "public"."recruitment_applications" as permissive for update to "authenticated" using (( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'recruitment.manage'::text) AS has_permission)) with check ((( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'recruitment.manage'::text) AS has_permission) AND ((reviewed_by IS NULL) OR (reviewed_by = ( SELECT auth.uid() AS uid)))));
create policy "phase10_valid_session" on "public"."recruitment_decisions" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "recruitment_decisions_read_directors" on "public"."recruitment_decisions" as permissive for select to "authenticated" using (( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'recruitment.manage'::text) AS has_permission));
create policy "phase10_valid_session" on "public"."rh_absence_requests" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "rh_absence_requests_read_own_or_director" on "public"."rh_absence_requests" as permissive for select to "authenticated" using ((((employee_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)) OR ( SELECT (private.has_permission(( SELECT auth.uid() AS uid), 'hr.team.view'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.absences.review'::text)) AS is_director)));
create policy "phase10_valid_session" on "public"."rh_disciplinary_reviews" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "rh_disciplinary_reviews_read_own_or_director" on "public"."rh_disciplinary_reviews" as permissive for select to "authenticated" using ((((employee_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)) OR ( SELECT (private.has_permission(( SELECT auth.uid() AS uid), 'hr.team.view'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.discipline.review'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.discipline.manage'::text)) AS is_director)));
create policy "phase10_valid_session" on "public"."rh_hour_justifications" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "rh_hour_justifications_read_own_or_director" on "public"."rh_hour_justifications" as permissive for select to "authenticated" using ((((employee_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)) OR ( SELECT (private.has_permission(( SELECT auth.uid() AS uid), 'hr.team.view'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.justifications.review'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.reports.view'::text)) AS is_director)));
create policy "phase10_valid_session" on "public"."rh_hour_snapshots" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "rh_hour_snapshots_read_own_or_director" on "public"."rh_hour_snapshots" as permissive for select to "authenticated" using ((((employee_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)) OR ( SELECT (private.has_permission(( SELECT auth.uid() AS uid), 'hr.team.view'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.hours.manage'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.hours.import'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.weeks.close'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.reports.view'::text)) AS is_director)));
create policy "phase10_valid_session" on "public"."rh_leave_week_adjustments" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "rh_leave_week_adjustments_read_own_or_director" on "public"."rh_leave_week_adjustments" as permissive for select to "authenticated" using ((((employee_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)) OR ( SELECT (private.has_permission(( SELECT auth.uid() AS uid), 'hr.team.view'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.absences.review'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.reports.view'::text)) AS is_director)));
create policy "phase10_valid_session" on "public"."rh_warnings" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "rh_warnings_read_own_or_director" on "public"."rh_warnings" as permissive for select to "authenticated" using ((((employee_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)) OR ( SELECT (private.has_permission(( SELECT auth.uid() AS uid), 'hr.team.view'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.warnings.issue'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.warnings.annul'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.discipline.review'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.reports.view'::text)) AS is_director)));
create policy "phase10_valid_session" on "public"."rh_week_closures" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "rh_week_closures_read_director" on "public"."rh_week_closures" as permissive for select to "authenticated" using (( SELECT (private.has_permission(( SELECT auth.uid() AS uid), 'hr.team.view'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.weeks.close'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.weeks.reopen'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.reports.view'::text)) AS is_director));
create policy "phase10_valid_session" on "public"."rh_week_reopen_events" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "rh_week_reopen_events_read_director" on "public"."rh_week_reopen_events" as permissive for select to "authenticated" using (( SELECT (private.has_permission(( SELECT auth.uid() AS uid), 'hr.team.view'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.weeks.reopen'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.reports.view'::text)) AS is_director));
create policy "phase10_valid_session" on "public"."rh_weekly_records" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "rh_weekly_records_read_own_or_director" on "public"."rh_weekly_records" as permissive for select to "authenticated" using ((((employee_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)) OR ( SELECT (private.has_permission(( SELECT auth.uid() AS uid), 'hr.team.view'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.weeks.close'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.weeks.reopen'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.reports.view'::text)) AS is_director)));
create policy "phase10_valid_session" on "public"."service_catalog" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "service_catalog_read_authorized" on "public"."service_catalog" as permissive for select to "authenticated" using (((active AND private.has_permission(( SELECT auth.uid() AS uid), 'catalog.view'::text)) OR private.has_permission(( SELECT auth.uid() AS uid), 'catalog.manage'::text)));
create policy "service_catalog_update_authorized" on "public"."service_catalog" as permissive for update to "authenticated" using (private.has_permission(( SELECT auth.uid() AS uid), 'catalog.manage'::text)) with check ((private.has_permission(( SELECT auth.uid() AS uid), 'catalog.manage'::text) AND (updated_by = ( SELECT auth.uid() AS uid))));
create policy "phase10_valid_session" on "public"."staff_course_records" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "staff_course_records_read_own_or_manager" on "public"."staff_course_records" as permissive for select to "authenticated" using (((employee_id = ( SELECT auth.uid() AS uid)) OR private.has_permission(( SELECT auth.uid() AS uid), 'courses.completions.manage'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.team.view'::text)));
create policy "phase10_valid_session" on "public"."staff_position_history" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "staff_position_history_read_own_or_manager" on "public"."staff_position_history" as permissive for select to "authenticated" using (((employee_id = ( SELECT auth.uid() AS uid)) OR private.has_permission(( SELECT auth.uid() AS uid), 'hr.team.view'::text) OR private.has_permission(( SELECT auth.uid() AS uid), 'progression.review'::text)));
create policy "phase10_valid_session" on "public"."staff_position_permissions" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "staff_position_permissions_read_manager" on "public"."staff_position_permissions" as permissive for select to "authenticated" using (private.has_permission(( SELECT auth.uid() AS uid), 'access.manage'::text));
create policy "phase10_valid_session" on "public"."staff_position_transition_rules" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "staff_position_transition_rules_read_authenticated" on "public"."staff_position_transition_rules" as permissive for select to "authenticated" using (true);
create policy "phase10_valid_session" on "public"."staff_positions" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "staff_positions_read_active_or_manager" on "public"."staff_positions" as permissive for select to "authenticated" using ((active OR private.has_permission(( SELECT auth.uid() AS uid), 'access.manage'::text)));
create policy "phase10_valid_session" on "public"."staff_promotion_reviews" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "staff_promotion_reviews_read_own_or_manager" on "public"."staff_promotion_reviews" as permissive for select to "authenticated" using (((employee_id = ( SELECT auth.uid() AS uid)) OR private.has_permission(( SELECT auth.uid() AS uid), 'progression.review'::text)));
create policy "phase10_valid_session" on "public"."system_permissions" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "system_permissions_read_authenticated" on "public"."system_permissions" as permissive for select to "authenticated" using (((( SELECT auth.uid() AS uid) IS NOT NULL) AND ( SELECT private.is_active_user() AS is_active_user)));
create policy "phase10_valid_session" on "public"."system_settings" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "settings_read_directors" on "public"."system_settings" as permissive for select to "authenticated" using (( SELECT private.has_permission(( SELECT auth.uid() AS uid), 'settings.critical'::text) AS is_director));
create policy "phase10_valid_session" on "public"."user_permission_grants" as restrictive for all to "authenticated" using (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid)) with check (( SELECT private.hpsm_session_valid(true) AS hpsm_session_valid));
create policy "user_permission_grants_read_own_or_manager" on "public"."user_permission_grants" as permissive for select to "authenticated" using (((user_id = ( SELECT auth.uid() AS uid)) OR private.has_permission(( SELECT auth.uid() AS uid), 'access.manage'::text)));

-- Triggers de aplicação.
CREATE TRIGGER attendance_items_audit AFTER INSERT OR DELETE OR UPDATE ON attendance_items FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER attendance_items_create_health_plan_request AFTER INSERT ON attendance_items FOR EACH ROW EXECUTE FUNCTION private.create_health_plan_request_from_sale();
CREATE TRIGGER attendance_cancel_closes_health_plan_request AFTER UPDATE OF status ON attendances FOR EACH ROW EXECUTE FUNCTION private.close_health_plan_request_on_attendance_cancel();
CREATE TRIGGER attendances_audit AFTER INSERT OR DELETE OR UPDATE ON attendances FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER attendances_guard_update BEFORE UPDATE ON attendances FOR EACH ROW EXECUTE FUNCTION private.guard_attendance_update();
CREATE TRIGGER attendances_touch_updated_at BEFORE UPDATE ON attendances FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER clinical_casts_guard_update BEFORE UPDATE ON clinical_casts FOR EACH ROW EXECUTE FUNCTION private.guard_clinical_cast_update();
CREATE TRIGGER clinical_casts_touch_updated_at BEFORE UPDATE ON clinical_casts FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER clinical_casts_validate_link BEFORE INSERT OR UPDATE OF patient_id, attendance_id ON clinical_casts FOR EACH ROW EXECUTE FUNCTION private.validate_clinical_cast_link();
CREATE TRIGGER clinical_exam_images_normalize_ai_metadata BEFORE INSERT OR UPDATE OF source, original_filename, caption ON clinical_exam_images FOR EACH ROW EXECUTE FUNCTION private.normalize_ai_clinical_exam_image_metadata();
CREATE TRIGGER clinical_exam_images_touch_updated_at BEFORE UPDATE ON clinical_exam_images FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER clinical_exams_discard_ai_image_drafts AFTER UPDATE OF status ON clinical_exams FOR EACH ROW EXECUTE FUNCTION private.discard_exam_ai_image_drafts_on_lock();
CREATE TRIGGER clinical_exams_prevent_meta_language BEFORE UPDATE OF status, technique, findings, conclusion, result_data ON clinical_exams FOR EACH ROW EXECUTE FUNCTION private.prevent_clinical_report_meta_language();
CREATE TRIGGER clinical_exams_protect_completed BEFORE UPDATE OF patient_id, exam_type_id, attendance_id, status, requested_by, responsible_professional_id, indication, clinical_context, technique, findings, conclusion, result_data, correction_reason, requested_at, started_at, submitted_for_review_at, completed_at, reviewed_by, final_report_snapshot ON clinical_exams FOR EACH ROW EXECUTE FUNCTION private.protect_completed_clinical_exam();
CREATE TRIGGER clinical_exams_touch_updated_at BEFORE UPDATE ON clinical_exams FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER clinical_exams_validate_link BEFORE INSERT OR UPDATE OF patient_id, attendance_id ON clinical_exams FOR EACH ROW EXECUTE FUNCTION private.validate_clinical_exam_link();
CREATE TRIGGER courses_audit AFTER INSERT OR DELETE OR UPDATE ON courses FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER courses_touch_updated_at BEFORE UPDATE ON courses FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER exam_ai_generations_current_prompt_version BEFORE INSERT ON exam_ai_generations FOR EACH ROW EXECUTE FUNCTION private.assign_current_exam_ai_prompt_version();
CREATE TRIGGER exam_ai_generations_protect_update BEFORE UPDATE ON exam_ai_generations FOR EACH ROW EXECUTE FUNCTION private.protect_exam_ai_generation_update();
CREATE TRIGGER exam_categories_touch_updated_at BEFORE UPDATE ON exam_categories FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER exam_types_touch_updated_at BEFORE UPDATE ON exam_types FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER notifications_health_plan_workflow AFTER INSERT OR UPDATE ON patient_health_plan_requests FOR EACH ROW EXECUTE FUNCTION private.notify_health_plan_workflow();
CREATE TRIGGER patient_health_plan_requests_audit AFTER INSERT OR UPDATE ON patient_health_plan_requests FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER patient_health_plan_requests_touch_updated_at BEFORE UPDATE ON patient_health_plan_requests FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER patients_audit AFTER INSERT OR DELETE OR UPDATE ON patients FOR EACH ROW EXECUTE FUNCTION private.audit_patient_change();
CREATE TRIGGER patients_guard_birth_date BEFORE INSERT OR UPDATE ON patients FOR EACH ROW EXECUTE FUNCTION private.enforce_patient_birth_date();
CREATE TRIGGER patients_guard_plan_changes BEFORE INSERT OR UPDATE ON patients FOR EACH ROW EXECUTE FUNCTION private.guard_patient_plan_changes();
CREATE TRIGGER patients_resolve_partnership_pending AFTER INSERT ON patients FOR EACH ROW EXECUTE FUNCTION private.resolve_partnership_pending_for_patient();
CREATE TRIGGER patients_touch_updated_at BEFORE UPDATE ON patients FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER plan_discounts_audit AFTER UPDATE ON plan_discounts FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER plan_discounts_touch_updated_at BEFORE UPDATE ON plan_discounts FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER profiles_audit AFTER INSERT OR DELETE OR UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER profiles_guard_director_general BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION private.guard_director_general();
CREATE TRIGGER profiles_guard_position_change BEFORE UPDATE OF position_id ON profiles FOR EACH ROW EXECUTE FUNCTION private.guard_profile_position_change();
CREATE TRIGGER profiles_provision_professional_identity AFTER INSERT ON profiles FOR EACH ROW EXECUTE FUNCTION private.provision_professional_identity();
CREATE TRIGGER profiles_record_initial_staff_position AFTER INSERT ON profiles FOR EACH ROW EXECUTE FUNCTION private.record_initial_staff_position();
CREATE TRIGGER profiles_touch_updated_at BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER notifications_recruitment_submission AFTER INSERT OR UPDATE ON recruitment_applications FOR EACH ROW EXECUTE FUNCTION private.notify_recruitment_submission();
CREATE TRIGGER recruitment_applications_audit AFTER UPDATE ON recruitment_applications FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER recruitment_touch_updated_at BEFORE UPDATE ON recruitment_applications FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER recruitment_decisions_audit AFTER INSERT ON recruitment_decisions FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER notifications_absence_workflow AFTER INSERT OR UPDATE ON rh_absence_requests FOR EACH ROW EXECUTE FUNCTION private.notify_absence_workflow();
CREATE TRIGGER rh_absence_requests_audit AFTER INSERT OR UPDATE ON rh_absence_requests FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER rh_absence_requests_touch_updated_at BEFORE UPDATE ON rh_absence_requests FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER notifications_disciplinary_workflow AFTER INSERT OR UPDATE ON rh_disciplinary_reviews FOR EACH ROW EXECUTE FUNCTION private.notify_disciplinary_workflow();
CREATE TRIGGER rh_disciplinary_reviews_audit AFTER INSERT OR UPDATE ON rh_disciplinary_reviews FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER rh_disciplinary_reviews_touch_updated_at BEFORE UPDATE ON rh_disciplinary_reviews FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER notifications_hour_justification AFTER INSERT OR UPDATE ON rh_hour_justifications FOR EACH ROW EXECUTE FUNCTION private.notify_hr_hour_justification();
CREATE TRIGGER rh_hour_justifications_audit AFTER INSERT OR UPDATE ON rh_hour_justifications FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER rh_hour_justifications_touch_updated_at BEFORE UPDATE ON rh_hour_justifications FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER rh_hour_snapshots_audit AFTER INSERT OR UPDATE ON rh_hour_snapshots FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER rh_hour_snapshots_touch_updated_at BEFORE UPDATE ON rh_hour_snapshots FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER rh_leave_week_adjustments_audit AFTER INSERT OR UPDATE ON rh_leave_week_adjustments FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER rh_leave_week_adjustments_touch_updated_at BEFORE UPDATE ON rh_leave_week_adjustments FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER notifications_warning_workflow AFTER INSERT OR UPDATE ON rh_warnings FOR EACH ROW EXECUTE FUNCTION private.notify_warning_workflow();
CREATE TRIGGER rh_warnings_audit AFTER INSERT OR UPDATE ON rh_warnings FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER rh_warnings_touch_updated_at BEFORE UPDATE ON rh_warnings FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER rh_week_closures_audit AFTER INSERT OR UPDATE ON rh_week_closures FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER rh_week_closures_touch_updated_at BEFORE UPDATE ON rh_week_closures FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER rh_week_reopen_events_audit AFTER INSERT ON rh_week_reopen_events FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER notifications_weekly_deficit AFTER INSERT OR UPDATE ON rh_weekly_records FOR EACH ROW EXECUTE FUNCTION private.notify_hr_week_deficit();
CREATE TRIGGER rh_weekly_records_audit AFTER INSERT OR UPDATE ON rh_weekly_records FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER rh_weekly_records_touch_updated_at BEFORE UPDATE ON rh_weekly_records FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER service_catalog_audit AFTER INSERT OR DELETE OR UPDATE ON service_catalog FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER service_catalog_touch_updated_at BEFORE UPDATE ON service_catalog FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER staff_course_records_audit AFTER INSERT OR DELETE OR UPDATE ON staff_course_records FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER staff_course_records_touch_updated_at BEFORE UPDATE ON staff_course_records FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER staff_position_history_audit AFTER INSERT OR DELETE OR UPDATE ON staff_position_history FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER staff_position_permissions_audit AFTER INSERT OR DELETE OR UPDATE ON staff_position_permissions FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER staff_position_transition_rules_audit AFTER INSERT OR DELETE OR UPDATE ON staff_position_transition_rules FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER staff_position_transition_rules_touch_updated_at BEFORE UPDATE ON staff_position_transition_rules FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER staff_positions_audit AFTER INSERT OR DELETE OR UPDATE ON staff_positions FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER staff_positions_touch_updated_at BEFORE UPDATE ON staff_positions FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER staff_promotion_reviews_audit AFTER INSERT OR DELETE OR UPDATE ON staff_promotion_reviews FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER staff_promotion_reviews_notify AFTER INSERT ON staff_promotion_reviews FOR EACH ROW EXECUTE FUNCTION private.notify_staff_promotion_review();
CREATE TRIGGER staff_promotion_reviews_touch_updated_at BEFORE UPDATE ON staff_promotion_reviews FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER settings_audit AFTER INSERT OR DELETE OR UPDATE ON system_settings FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER settings_touch_updated_at BEFORE UPDATE ON system_settings FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER user_permission_grants_audit AFTER INSERT OR DELETE OR UPDATE ON user_permission_grants FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER enforce_bucket_name_length_trigger BEFORE INSERT OR UPDATE OF name ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.enforce_bucket_name_length();
CREATE TRIGGER protect_buckets_delete BEFORE DELETE ON storage.buckets FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();
CREATE TRIGGER protect_objects_delete BEFORE DELETE ON storage.objects FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();
CREATE TRIGGER update_objects_updated_at BEFORE UPDATE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.update_updated_at_column();

-- Grants de tabelas expostas.
grant SELECT on table "public"."attendance_items" to "authenticated";
grant INSERT, SELECT on table "public"."attendance_items" to "service_role";
grant SELECT on table "public"."attendances" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."attendances" to "service_role";
grant SELECT on table "public"."audit_logs" to "authenticated";
grant SELECT on table "public"."audit_logs" to "service_role";
grant SELECT on table "public"."benefit_plans" to "authenticated";
grant SELECT on table "public"."benefit_plans" to "service_role";
grant SELECT on table "public"."clinical_casts" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."clinical_casts" to "service_role";
grant DELETE, INSERT, SELECT, UPDATE on table "public"."clinical_exam_document_shares" to "service_role";
grant DELETE, INSERT, SELECT, UPDATE on table "public"."clinical_exam_documents" to "service_role";
grant SELECT on table "public"."clinical_exam_images" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."clinical_exam_images" to "service_role";
grant SELECT on table "public"."clinical_exam_report_versions" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."clinical_exam_report_versions" to "service_role";
grant SELECT on table "public"."clinical_exam_status_history" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."clinical_exam_status_history" to "service_role";
grant SELECT on table "public"."clinical_exams" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."clinical_exams" to "service_role";
grant SELECT on table "public"."courses" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."courses" to "service_role";
grant SELECT on table "public"."dashboard_preferences" to "authenticated";
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table "public"."dashboard_preferences" to "service_role";
grant SELECT on table "public"."exam_ai_generations" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."exam_ai_generations" to "service_role";
grant SELECT on table "public"."exam_categories" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."exam_categories" to "service_role";
grant SELECT on table "public"."exam_types" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."exam_types" to "service_role";
grant SELECT on table "public"."notification_reads" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."notification_reads" to "service_role";
grant SELECT on table "public"."notifications" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."notifications" to "service_role";
grant SELECT on table "public"."patient_directory" to "authenticated";
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table "public"."patient_directory" to "service_role";
grant SELECT on table "public"."patient_health_plan_requests" to "authenticated";
grant DELETE, INSERT, SELECT, UPDATE on table "public"."patient_health_plan_requests" to "service_role";
grant INSERT, SELECT, UPDATE on table "public"."patients" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."patients" to "service_role";
grant SELECT on table "public"."plan_discounts" to "authenticated";
grant DELETE, INSERT, SELECT, UPDATE on table "public"."plan_discounts" to "service_role";
grant SELECT on table "public"."professional_identities" to "authenticated";
grant SELECT on table "public"."professional_identities" to "service_role";
grant SELECT on table "public"."profiles" to "authenticated";
grant DELETE, INSERT, SELECT, UPDATE on table "public"."profiles" to "service_role";
grant SELECT on table "public"."recruitment_applications" to "authenticated";
grant DELETE, INSERT, SELECT, UPDATE on table "public"."recruitment_applications" to "service_role";
grant SELECT on table "public"."recruitment_decisions" to "authenticated";
grant DELETE, INSERT, SELECT, UPDATE on table "public"."recruitment_decisions" to "service_role";
grant SELECT on table "public"."rh_absence_requests" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."rh_absence_requests" to "service_role";
grant SELECT on table "public"."rh_disciplinary_reviews" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."rh_disciplinary_reviews" to "service_role";
grant SELECT on table "public"."rh_hour_justifications" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."rh_hour_justifications" to "service_role";
grant SELECT on table "public"."rh_hour_snapshots" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."rh_hour_snapshots" to "service_role";
grant SELECT on table "public"."rh_leave_week_adjustments" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."rh_leave_week_adjustments" to "service_role";
grant SELECT on table "public"."rh_warnings" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."rh_warnings" to "service_role";
grant SELECT on table "public"."rh_week_closures" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."rh_week_closures" to "service_role";
grant SELECT on table "public"."rh_week_reopen_events" to "authenticated";
grant INSERT, SELECT on table "public"."rh_week_reopen_events" to "service_role";
grant SELECT on table "public"."rh_weekly_records" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."rh_weekly_records" to "service_role";
grant SELECT on table "public"."service_catalog" to "authenticated";
grant DELETE, INSERT, SELECT, UPDATE on table "public"."service_catalog" to "service_role";
grant SELECT on table "public"."staff_course_records" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."staff_course_records" to "service_role";
grant SELECT on table "public"."staff_position_history" to "authenticated";
grant DELETE, INSERT, SELECT, UPDATE on table "public"."staff_position_history" to "service_role";
grant SELECT on table "public"."staff_position_permissions" to "authenticated";
grant DELETE, INSERT, SELECT, UPDATE on table "public"."staff_position_permissions" to "service_role";
grant SELECT on table "public"."staff_position_transition_rules" to "authenticated";
grant DELETE, INSERT, SELECT, UPDATE on table "public"."staff_position_transition_rules" to "service_role";
grant SELECT on table "public"."staff_positions" to "authenticated";
grant DELETE, INSERT, SELECT, UPDATE on table "public"."staff_positions" to "service_role";
grant SELECT on table "public"."staff_promotion_reviews" to "authenticated";
grant DELETE, INSERT, SELECT, UPDATE on table "public"."staff_promotion_reviews" to "service_role";
grant SELECT on table "public"."system_permissions" to "authenticated";
grant SELECT on table "public"."system_permissions" to "service_role";
grant SELECT on table "public"."system_settings" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."system_settings" to "service_role";
grant SELECT on table "public"."user_permission_grants" to "authenticated";
grant INSERT, SELECT, UPDATE on table "public"."user_permission_grants" to "service_role";

-- Grants de rotinas (inventário por specific_name; migrations são a fonte executável).
-- ROUTINE_GRANT public.annul_hr_warning [annul_hr_warning_18313] EXECUTE TO service_role
-- ROUTINE_GRANT public.apply_and_submit_clinical_exam_ai_generation [apply_and_submit_clinical_exam_ai_generation_22076] EXECUTE TO service_role
-- ROUTINE_GRANT public.apply_clinical_exam_ai_bundle [apply_clinical_exam_ai_bundle_21776] EXECUTE TO service_role
-- ROUTINE_GRANT public.apply_clinical_exam_ai_generation [apply_clinical_exam_ai_generation_21690] EXECUTE TO authenticated
-- ROUTINE_GRANT public.apply_clinical_exam_ai_image [apply_clinical_exam_ai_image_21724] EXECUTE TO service_role
-- ROUTINE_GRANT public.appoint_staff_position [appoint_staff_position_20588] EXECUTE TO service_role
-- ROUTINE_GRANT public.archive_notification_announcement [archive_notification_announcement_18392] EXECUTE TO service_role
-- ROUTINE_GRANT public.assign_initial_staff_position [assign_initial_staff_position_20632] EXECUTE TO service_role
-- ROUTINE_GRANT public.begin_clinical_exam_ai_generation [begin_clinical_exam_ai_generation_21686] EXECUTE TO service_role
-- ROUTINE_GRANT public.begin_clinical_exam_ai_generation [begin_clinical_exam_ai_generation_21773] EXECUTE TO service_role
-- ROUTINE_GRANT public.begin_clinical_exam_ai_image [begin_clinical_exam_ai_image_21721] EXECUTE TO service_role
-- ROUTINE_GRANT public.begin_professional_identity_generation [begin_professional_identity_generation_23648] EXECUTE TO service_role
-- ROUTINE_GRANT private.can_view_notification [can_view_notification_18390] EXECUTE TO authenticated
-- ROUTINE_GRANT private.can_view_notification [can_view_notification_18390] EXECUTE TO service_role
-- ROUTINE_GRANT public.cancel_attendance [cancel_attendance_17696] EXECUTE TO authenticated
-- ROUTINE_GRANT public.cancel_attendance [cancel_attendance_17696] EXECUTE TO service_role
-- ROUTINE_GRANT private.cancel_attendance [cancel_attendance_23348] EXECUTE TO authenticated
-- ROUTINE_GRANT private.cancel_attendance [cancel_attendance_23348] EXECUTE TO service_role
-- ROUTINE_GRANT public.cancel_clinical_cast [cancel_clinical_cast_22751] EXECUTE TO authenticated
-- ROUTINE_GRANT public.cancel_hr_leave_request [cancel_hr_leave_request_18720] EXECUTE TO service_role
-- ROUTINE_GRANT public.cancel_partnership_pending [cancel_partnership_pending_25425] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_cast_attendance_options [clinical_cast_attendance_options_22746] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_cast_detail [clinical_cast_detail_22745] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_cast_overdue_page [clinical_cast_overdue_page_22781] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_cast_page [clinical_cast_page_22744] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_exam_ai_context [clinical_exam_ai_context_21685] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_exam_ai_generations [clinical_exam_ai_generations_21692] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_exam_ai_image_context [clinical_exam_ai_image_context_21720] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_exam_ai_image_draft [clinical_exam_ai_image_draft_21723] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_exam_ai_visual_input [clinical_exam_ai_visual_input_21772] EXECUTE TO service_role
-- ROUTINE_GRANT public.clinical_exam_attendance_options [clinical_exam_attendance_options_21212] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_exam_detail [clinical_exam_detail_21210] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_exam_detail [clinical_exam_detail_21210] EXECUTE TO service_role
-- ROUTINE_GRANT public.clinical_exam_document_state [clinical_exam_document_state_22498] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_exam_image_gallery [clinical_exam_image_gallery_21410] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_exam_image_gallery [clinical_exam_image_gallery_21410] EXECUTE TO service_role
-- ROUTINE_GRANT public.clinical_exam_image_upload_context [clinical_exam_image_upload_context_21411] EXECUTE TO service_role
-- ROUTINE_GRANT public.clinical_exam_imaging_template_catalog [clinical_exam_imaging_template_catalog_21408] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_exam_imaging_template_catalog [clinical_exam_imaging_template_catalog_21408] EXECUTE TO service_role
-- ROUTINE_GRANT public.clinical_exam_page [clinical_exam_page_21209] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_exam_page [clinical_exam_page_21209] EXECUTE TO service_role
-- ROUTINE_GRANT public.clinical_exam_reference_data [clinical_exam_reference_data_21211] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_exam_template_catalog [clinical_exam_template_catalog_21251] EXECUTE TO authenticated
-- ROUTINE_GRANT public.clinical_exam_template_catalog [clinical_exam_template_catalog_21251] EXECUTE TO service_role
-- ROUTINE_GRANT public.close_hr_week [close_hr_week_18311] EXECUTE TO service_role
-- ROUTINE_GRANT public.complete_clinical_exam_ai_generation [complete_clinical_exam_ai_generation_21688] EXECUTE TO service_role
-- ROUTINE_GRANT public.complete_clinical_exam_ai_image [complete_clinical_exam_ai_image_21722] EXECUTE TO service_role
-- ROUTINE_GRANT public.complete_professional_identity_generation [complete_professional_identity_generation_23649] EXECUTE TO service_role
-- ROUTINE_GRANT public.correct_professional_identity_crm [correct_professional_identity_crm_23651] EXECUTE TO authenticated
-- ROUTINE_GRANT public.correct_professional_identity_crm [correct_professional_identity_crm_23651] EXECUTE TO service_role
-- ROUTINE_GRANT private.create_attendance [create_attendance_25442] EXECUTE TO authenticated
-- ROUTINE_GRANT private.create_attendance [create_attendance_25442] EXECUTE TO service_role
-- ROUTINE_GRANT public.create_attendance [create_attendance_25444] EXECUTE TO authenticated
-- ROUTINE_GRANT public.create_attendance [create_attendance_25444] EXECUTE TO service_role
-- ROUTINE_GRANT public.create_clinical_cast [create_clinical_cast_22747] EXECUTE TO authenticated
-- ROUTINE_GRANT public.create_clinical_exam [create_clinical_exam_21831] EXECUTE TO authenticated
-- ROUTINE_GRANT public.create_clinical_exam_document_share [create_clinical_exam_document_share_22500] EXECUTE TO authenticated
-- ROUTINE_GRANT public.create_course [create_course_20592] EXECUTE TO service_role
-- ROUTINE_GRANT public.create_hr_leave_request [create_hr_leave_request_18719] EXECUTE TO service_role
-- ROUTINE_GRANT public.create_partnership [create_partnership_25420] EXECUTE TO authenticated
-- ROUTINE_GRANT public.create_staff_position [create_staff_position_19139] EXECUTE TO service_role
-- ROUTINE_GRANT private.current_position_level [current_position_level_20345] EXECUTE TO service_role
-- ROUTINE_GRANT public.decide_hr_disciplinary_review [decide_hr_disciplinary_review_18314] EXECUTE TO service_role
-- ROUTINE_GRANT public.decide_recruitment_application [decide_recruitment_application_17887] EXECUTE TO service_role
-- ROUTINE_GRANT public.decide_staff_promotion_review [decide_staff_promotion_review_20587] EXECUTE TO service_role
-- ROUTINE_GRANT public.delete_clinical_exam [delete_clinical_exam_21837] EXECUTE TO authenticated
-- ROUTINE_GRANT public.discard_clinical_exam_ai_generation [discard_clinical_exam_ai_generation_21691] EXECUTE TO authenticated
-- ROUTINE_GRANT public.discard_clinical_exam_ai_image [discard_clinical_exam_ai_image_21725] EXECUTE TO service_role
-- ROUTINE_GRANT public.effective_permission_codes [effective_permission_codes_20825] EXECUTE TO service_role
-- ROUTINE_GRANT public.fail_clinical_exam_ai_generation [fail_clinical_exam_ai_generation_21689] EXECUTE TO service_role
-- ROUTINE_GRANT public.fail_professional_identity_generation [fail_professional_identity_generation_23650] EXECUTE TO service_role
-- ROUTINE_GRANT public.finalize_hr_week_closure [finalize_hr_week_closure_18725] EXECUTE TO service_role
-- ROUTINE_GRANT private.get_staff_progression_status [get_staff_progression_status_20583] EXECUTE TO service_role
-- ROUTINE_GRANT public.get_staff_progression_status [get_staff_progression_status_20585] EXECUTE TO service_role
-- ROUTINE_GRANT public.get_staff_progression_statuses [get_staff_progression_statuses_22803] EXECUTE TO service_role
-- ROUTINE_GRANT public.grant_temporary_permission [grant_temporary_permission_19142] EXECUTE TO service_role
-- ROUTINE_GRANT public.grant_user_permission [grant_user_permission_20347] EXECUTE TO service_role
-- ROUTINE_GRANT private.has_any_management_permission [has_any_management_permission_19138] EXECUTE TO service_role
-- ROUTINE_GRANT private.has_permission [has_permission_19137] EXECUTE TO authenticated
-- ROUTINE_GRANT private.has_permission [has_permission_19137] EXECUTE TO service_role
-- ROUTINE_GRANT public.hpsm_attendance_history [hpsm_attendance_history_21597] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_attendance_history_page [hpsm_attendance_history_page_22811] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_audit_page [hpsm_audit_page_22805] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_audit_page [hpsm_audit_page_22805] EXECUTE TO service_role
-- ROUTINE_GRANT public.hpsm_dashboard_bundle [hpsm_dashboard_bundle_23579] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_dashboard_bundle [hpsm_dashboard_bundle_23579] EXECUTE TO service_role
-- ROUTINE_GRANT public.hpsm_dashboard_summary [hpsm_dashboard_summary_21596] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_global_search [hpsm_global_search_23143] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_hr_production [hpsm_hr_production_22807] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_hr_production [hpsm_hr_production_22807] EXECUTE TO service_role
-- ROUTINE_GRANT private.hpsm_identity_is_director_general [hpsm_identity_is_director_general_23643] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_my_hr_snapshot [hpsm_my_hr_snapshot_21598] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_operational_catalog [hpsm_operational_catalog_22814] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_partnership_detail [hpsm_partnership_detail_25417] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_partnership_member_page [hpsm_partnership_member_page_25418] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_partnership_page [hpsm_partnership_page_25416] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_partnership_patient_lookup [hpsm_partnership_patient_lookup_25419] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_patient_quick_lookup [hpsm_patient_quick_lookup_22813] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_report_financial [hpsm_report_financial_23181] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_report_hr [hpsm_report_hr_23179] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_report_individual [hpsm_report_individual_23184] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_report_overview [hpsm_report_overview_23178] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_report_partnerships [hpsm_report_partnerships_25447] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_report_staff_search [hpsm_report_staff_search_23177] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_report_team [hpsm_report_team_23183] EXECUTE TO authenticated
-- ROUTINE_GRANT public.hpsm_session_bootstrap [hpsm_session_bootstrap_21595] EXECUTE TO authenticated
-- ROUTINE_GRANT private.hpsm_session_valid [hpsm_session_valid_23297] EXECUTE TO authenticated
-- ROUTINE_GRANT private.hpsm_session_valid [hpsm_session_valid_23297] EXECUTE TO service_role
-- ROUTINE_GRANT public.hpsm_shell_snapshot [hpsm_shell_snapshot_21599] EXECUTE TO authenticated
-- ROUTINE_GRANT public.import_hr_hour_snapshots [import_hr_hour_snapshots_18727] EXECUTE TO service_role
-- ROUTINE_GRANT public.import_partnership_people [import_partnership_people_25423] EXECUTE TO authenticated
-- ROUTINE_GRANT private.is_active_user [is_active_user_17585] EXECUTE TO authenticated
-- ROUTINE_GRANT private.is_director [is_director_17575] EXECUTE TO authenticated
-- ROUTINE_GRANT public.issue_hr_warning [issue_hr_warning_18728] EXECUTE TO service_role
-- ROUTINE_GRANT public.manage_exam_category [manage_exam_category_21219] EXECUTE TO authenticated
-- ROUTINE_GRANT public.manage_exam_category [manage_exam_category_21219] EXECUTE TO service_role
-- ROUTINE_GRANT public.manage_exam_imaging_template [manage_exam_imaging_template_21409] EXECUTE TO authenticated
-- ROUTINE_GRANT public.manage_exam_imaging_template [manage_exam_imaging_template_21409] EXECUTE TO service_role
-- ROUTINE_GRANT public.manage_exam_template [manage_exam_template_21252] EXECUTE TO authenticated
-- ROUTINE_GRANT public.manage_exam_template [manage_exam_template_21252] EXECUTE TO service_role
-- ROUTINE_GRANT public.manage_exam_type [manage_exam_type_21220] EXECUTE TO authenticated
-- ROUTINE_GRANT public.manage_exam_type [manage_exam_type_21220] EXECUTE TO service_role
-- ROUTINE_GRANT public.mark_all_notifications_read [mark_all_notifications_read_18394] EXECUTE TO service_role
-- ROUTINE_GRANT public.mark_notification_read [mark_notification_read_18393] EXECUTE TO service_role
-- ROUTINE_GRANT public.override_staff_position [override_staff_position_20835] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_active_clinical_casts [patient_active_clinical_casts_22780] EXECUTE TO authenticated
-- ROUTINE_GRANT public.patient_activity_page [patient_activity_page_20836] EXECUTE TO authenticated
-- ROUTINE_GRANT public.patient_activity_page [patient_activity_page_20836] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_clinical_exam_page [patient_clinical_exam_page_21559] EXECUTE TO authenticated
-- ROUTINE_GRANT public.patient_clinical_exam_page [patient_clinical_exam_page_21559] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_partnership_page [patient_partnership_page_25427] EXECUTE TO authenticated
-- ROUTINE_GRANT public.patient_plan_history_page [patient_plan_history_page_20822] EXECUTE TO authenticated
-- ROUTINE_GRANT public.patient_plan_history_page [patient_plan_history_page_20822] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_attendance_detail [patient_portal_attendance_detail_22943] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_attendance_page [patient_portal_attendance_page_22942] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_cancel_partnership_pending [patient_portal_cancel_partnership_pending_25432] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_cast_page [patient_portal_cast_page_23039] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_create_clinical_exam_document_share [patient_portal_create_clinical_exam_document_share_22998] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_create_session [patient_portal_create_session_22872] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_exam_detail [patient_portal_exam_detail_22994] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_exam_document_state [patient_portal_exam_document_state_22996] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_exam_image [patient_portal_exam_image_22995] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_exam_page [patient_portal_exam_page_22993] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_health_plan_page [patient_portal_health_plan_page_23038] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_history_page [patient_portal_history_page_22940] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_import_partnership_people [patient_portal_import_partnership_people_25430] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_partnership_member_page [patient_portal_partnership_member_page_25429] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_partnership_page [patient_portal_partnership_page_25428] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_register_clinical_exam_document [patient_portal_register_clinical_exam_document_22997] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_revoke_session [patient_portal_revoke_session_22874] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_session_me [patient_portal_session_me_22873] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_summary [patient_portal_summary_22910] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_portal_unlink_partnership_member [patient_portal_unlink_partnership_member_25431] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_profile_summary [patient_profile_summary_20820] EXECUTE TO authenticated
-- ROUTINE_GRANT public.patient_profile_summary [patient_profile_summary_20820] EXECUTE TO service_role
-- ROUTINE_GRANT public.patient_timeline [patient_timeline_20823] EXECUTE TO authenticated
-- ROUTINE_GRANT public.prepare_professional_identity_regeneration [prepare_professional_identity_regeneration_23653] EXECUTE TO authenticated
-- ROUTINE_GRANT public.prepare_professional_identity_regeneration [prepare_professional_identity_regeneration_23653] EXECUTE TO service_role
-- ROUTINE_GRANT public.professional_identity_generation_context [professional_identity_generation_context_23647] EXECUTE TO authenticated
-- ROUTINE_GRANT public.professional_identity_generation_context [professional_identity_generation_context_23647] EXECUTE TO service_role
-- ROUTINE_GRANT public.publish_notification_announcement [publish_notification_announcement_18391] EXECUTE TO service_role
-- ROUTINE_GRANT public.record_hr_hour_snapshot [record_hr_hour_snapshot_18309] EXECUTE TO service_role
-- ROUTINE_GRANT public.record_staff_course_status [record_staff_course_status_20594] EXECUTE TO service_role
-- ROUTINE_GRANT public.refresh_staff_promotion_reviews [refresh_staff_promotion_reviews_20586] EXECUTE TO service_role
-- ROUTINE_GRANT public.register_clinical_exam_document [register_clinical_exam_document_22499] EXECUTE TO authenticated
-- ROUTINE_GRANT public.register_clinical_exam_image [register_clinical_exam_image_21412] EXECUTE TO service_role
-- ROUTINE_GRANT public.remove_clinical_cast [remove_clinical_cast_22750] EXECUTE TO authenticated
-- ROUTINE_GRANT public.remove_clinical_exam_image [remove_clinical_exam_image_21413] EXECUTE TO authenticated
-- ROUTINE_GRANT public.remove_clinical_exam_image [remove_clinical_exam_image_21413] EXECUTE TO service_role
-- ROUTINE_GRANT public.reopen_hr_week_closure [reopen_hr_week_closure_18726] EXECUTE TO service_role
-- ROUTINE_GRANT public.resolve_clinical_exam_document_share [resolve_clinical_exam_document_share_22502] EXECUTE TO service_role
-- ROUTINE_GRANT public.restore_clinical_exam_image [restore_clinical_exam_image_21414] EXECUTE TO authenticated
-- ROUTINE_GRANT public.restore_clinical_exam_image [restore_clinical_exam_image_21414] EXECUTE TO service_role
-- ROUTINE_GRANT public.review_clinical_exam [review_clinical_exam_21218] EXECUTE TO authenticated
-- ROUTINE_GRANT public.review_hr_absence [review_hr_absence_18310] EXECUTE TO service_role
-- ROUTINE_GRANT public.review_hr_hour_justification [review_hr_hour_justification_18724] EXECUTE TO service_role
-- ROUTINE_GRANT public.review_hr_leave_request [review_hr_leave_request_18721] EXECUTE TO service_role
-- ROUTINE_GRANT public.review_partnership_pending [review_partnership_pending_25426] EXECUTE TO authenticated
-- ROUTINE_GRANT private.review_patient_health_plan_request [review_patient_health_plan_request_20707] EXECUTE TO authenticated
-- ROUTINE_GRANT private.review_patient_health_plan_request [review_patient_health_plan_request_20707] EXECUTE TO service_role
-- ROUTINE_GRANT public.review_patient_health_plan_request [review_patient_health_plan_request_20710] EXECUTE TO authenticated
-- ROUTINE_GRANT public.review_patient_health_plan_request [review_patient_health_plan_request_20710] EXECUTE TO service_role
-- ROUTINE_GRANT public.revoke_clinical_exam_document_share [revoke_clinical_exam_document_share_22501] EXECUTE TO authenticated
-- ROUTINE_GRANT public.revoke_temporary_permission [revoke_temporary_permission_19143] EXECUTE TO service_role
-- ROUTINE_GRANT public.save_clinical_exam_draft [save_clinical_exam_draft_21216] EXECUTE TO authenticated
-- ROUTINE_GRANT public.save_clinical_exam_draft [save_clinical_exam_draft_21216] EXECUTE TO service_role
-- ROUTINE_GRANT public.save_dashboard_preferences [save_dashboard_preferences_23578] EXECUTE TO authenticated
-- ROUTINE_GRANT public.save_dashboard_preferences [save_dashboard_preferences_23578] EXECUTE TO service_role
-- ROUTINE_GRANT public.set_partnership_status [set_partnership_status_25422] EXECUTE TO authenticated
-- ROUTINE_GRANT public.set_staff_position_permissions [set_staff_position_permissions_19141] EXECUTE TO service_role
-- ROUTINE_GRANT public.set_warning_progression_impact [set_warning_progression_impact_20589] EXECUTE TO service_role
-- ROUTINE_GRANT private.staff_worked_minutes_since [staff_worked_minutes_since_20834] EXECUTE TO service_role
-- ROUTINE_GRANT public.start_clinical_exam [start_clinical_exam_21215] EXECUTE TO authenticated
-- ROUTINE_GRANT public.start_clinical_exam [start_clinical_exam_21215] EXECUTE TO service_role
-- ROUTINE_GRANT public.submit_clinical_exam_review [submit_clinical_exam_review_21217] EXECUTE TO authenticated
-- ROUTINE_GRANT public.submit_clinical_exam_review [submit_clinical_exam_review_21217] EXECUTE TO service_role
-- ROUTINE_GRANT public.submit_hr_hour_justification [submit_hr_hour_justification_18723] EXECUTE TO service_role
-- ROUTINE_GRANT public.unlink_patient_partnership [unlink_patient_partnership_25424] EXECUTE TO authenticated
-- ROUTINE_GRANT public.unlock_professional_identity_reprocess [unlock_professional_identity_reprocess_23652] EXECUTE TO authenticated
-- ROUTINE_GRANT public.unlock_professional_identity_reprocess [unlock_professional_identity_reprocess_23652] EXECUTE TO service_role
-- ROUTINE_GRANT public.update_catalog_pricing [update_catalog_pricing_17815] EXECUTE TO authenticated
-- ROUTINE_GRANT public.update_clinical_cast_expected_removal [update_clinical_cast_expected_removal_22749] EXECUTE TO authenticated
-- ROUTINE_GRANT public.update_course [update_course_20593] EXECUTE TO service_role
-- ROUTINE_GRANT public.update_partnership [update_partnership_25421] EXECUTE TO authenticated
-- ROUTINE_GRANT public.update_staff_position [update_staff_position_19140] EXECUTE TO service_role

-- Buckets relevantes (configuração; nenhum objeto foi exportado).
-- BUCKET catalog-images public=false file_size_limit=2097152 mime=["image/jpeg","image/png","image/webp"]
-- BUCKET clinical-exam-documents public=false file_size_limit=12582912 mime=["image/png"]
-- BUCKET clinical-exam-images public=false file_size_limit=10485760 mime=["image/jpeg","image/png","image/webp"]
-- BUCKET professional-identities public=false file_size_limit=5242880 mime=["image/png"]


-- ============================================================
-- Delta estrutural efetivo posterior ao snapshot HPSM 1.0.0.
-- As definições abaixo consolidam o estado final das migrations
-- de preço rápido, plano administrativo e limites por atendimento.
-- Nenhum dado operacional está incluído.
-- ============================================================

-- A função de sessão é privada; as RPCs invocadoras usam auth.uid() e
-- repetem a sessão/permissão por private.has_permission e pelas policies RLS.

create or replace function public.update_catalog_unit_price(
  p_service_id bigint,
  p_unit_price numeric
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_unit_price numeric(18, 2);
begin
  if v_actor is null or not private.has_permission(v_actor, 'catalog.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para alterar preços.';
  end if;

  if p_service_id is null or p_service_id < 1 then
    raise exception using errcode = '22023', message = 'Selecione um item válido.';
  end if;

  if p_unit_price is null
     or p_unit_price = 'NaN'::numeric
     or p_unit_price < 0
     or p_unit_price > 9999999999999999.99 then
    raise exception using errcode = '22023', message = 'Informe um preço válido entre R$ 0,00 e R$ 9.999.999.999.999.999,99.';
  end if;

  v_unit_price := round(p_unit_price, 2);

  update public.service_catalog
  set unit_price = v_unit_price,
      updated_by = v_actor
  where id = p_service_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Item não localizado.';
  end if;

  return jsonb_build_object(
    'service_id', p_service_id,
    'unit_price', v_unit_price
  );
end;
$$;

create or replace function public.update_catalog_discounts_bulk(
  p_discounts jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_valid_count integer;
  v_service_count integer;
  v_discount_count integer;
  v_updated_count integer;
  v_discounts jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'catalog.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para alterar os descontos.';
  end if;

  if p_discounts is null
     or jsonb_typeof(p_discounts) <> 'array'
     or jsonb_array_length(p_discounts) <> 3 then
    raise exception using errcode = '22023', message = 'Informe os três descontos: Plano de Saúde, Parceiros do HP e Policiais/Arcanjos.';
  end if;

  select count(*)
  into v_valid_count
  from jsonb_to_recordset(p_discounts) as item(plan_code text, discount_percent numeric)
  join public.benefit_plans plan on plan.code = item.plan_code
  where item.discount_percent is not null
    and item.discount_percent <> 'NaN'::numeric
    and item.discount_percent between 0 and 100;

  if v_valid_count <> 3
     or exists (
       select 1
       from jsonb_to_recordset(p_discounts) as item(plan_code text, discount_percent numeric)
       group by item.plan_code
       having count(*) <> 1
     ) then
    raise exception using errcode = '22023', message = 'Cada desconto deve aparecer uma vez e estar entre 0% e 100%.';
  end if;

  select count(*) into v_service_count
  from public.service_catalog;

  select count(*) into v_discount_count
  from public.plan_discounts;

  if v_discount_count <> v_service_count * 3 then
    raise exception using errcode = 'P0001', message = 'A configuração atual dos descontos está incompleta. Nenhuma alteração foi aplicada.';
  end if;

  with input as (
    select
      item.plan_code,
      round(item.discount_percent, 2) as discount_percent
    from jsonb_to_recordset(p_discounts) as item(plan_code text, discount_percent numeric)
  )
  update public.plan_discounts discount
  set discount_percent = input.discount_percent,
      updated_by = v_actor
  from input
  where discount.plan_code = input.plan_code
    and discount.discount_percent is distinct from input.discount_percent;

  get diagnostics v_updated_count = row_count;

  select jsonb_object_agg(item.plan_code, round(item.discount_percent, 2))
  into v_discounts
  from jsonb_to_recordset(p_discounts) as item(plan_code text, discount_percent numeric);

  return jsonb_build_object(
    'service_count', v_service_count,
    'updated_rows', v_updated_count,
    'discounts', v_discounts
  );
end;
$$;

revoke all on function public.update_catalog_unit_price(bigint, numeric)
from public, anon, authenticated, service_role;
grant execute on function public.update_catalog_unit_price(bigint, numeric)
to authenticated;

revoke all on function public.update_catalog_discounts_bulk(jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.update_catalog_discounts_bulk(jsonb)
to authenticated;

notify pgrst, 'reload schema';

-- HPSM pós-1.0: concessão e ajuste administrativo do Plano de Saúde.
-- O fluxo é separado de vendas, não gera valor e permanece no histórico canônico.

alter table public.patient_health_plan_requests
  alter column attendance_id drop not null,
  add column origin text not null default 'sale',
  add column administrative_action text;

alter table public.patient_health_plan_requests
  add constraint patient_health_plan_requests_origin_check check (
    (
      origin = 'sale'
      and attendance_id is not null
      and administrative_action is null
    )
    or
    (
      origin = 'administrative'
      and attendance_id is null
      and status = 'approved'
      and administrative_action in ('grant', 'expiry_adjustment')
    )
  );

comment on column public.patient_health_plan_requests.origin is
  'Origem financeira (sale) ou concessão/ajuste administrativo sem cobrança.';
comment on column public.patient_health_plan_requests.administrative_action is
  'Ação administrativa append-only: grant ou expiry_adjustment.';

-- Renovações financeiras passam a partir da cobertura efetiva mais recente,
-- inclusive quando a Diretoria ajustou a data após uma venda anterior.
create or replace function private.review_patient_health_plan_request(
  p_request_id bigint,
  p_decision text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_current_end timestamptz;
  v_decided_at timestamptz := now();
  v_request public.patient_health_plan_requests%rowtype;
  v_start timestamptz;
begin
  if v_actor_id is null or not private.has_permission(v_actor_id, 'healthplans.review') then
    raise exception 'Você não possui permissão para analisar planos de saúde.' using errcode = '42501';
  end if;

  if p_decision not in ('approved', 'rejected') then
    raise exception 'Decisão inválida.' using errcode = '22023';
  end if;

  select request.*
  into v_request
  from public.patient_health_plan_requests request
  where request.id = p_request_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitação não localizada.';
  end if;

  if v_request.status <> 'pending' then
    if v_request.status = p_decision then
      return jsonb_build_object(
        'id', v_request.id,
        'status', v_request.status,
        'valid_until', v_request.coverage_end,
        'already_reviewed', true
      );
    end if;
    raise exception using errcode = 'P0001', message = 'A solicitação já possui uma decisão diferente.';
  end if;

  perform 1
  from public.patients patient
  where patient.id = v_request.patient_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Paciente não localizado.';
  end if;

  if p_decision = 'approved' then
    select request.coverage_end
    into v_current_end
    from public.patient_health_plan_requests request
    where request.patient_id = v_request.patient_id
      and request.status = 'approved'
    order by request.reviewed_at desc nulls last, request.id desc
    limit 1;

    v_start := greatest(v_decided_at, coalesce(v_current_end, v_decided_at));

    update public.patient_health_plan_requests
    set status = 'approved',
        reviewed_by = v_actor_id,
        reviewed_at = v_decided_at,
        rejection_reason = null,
        coverage_start = v_start,
        coverage_end = v_start + interval '30 days'
    where id = v_request.id
    returning * into v_request;
  else
    if char_length(btrim(coalesce(p_reason, ''))) < 10 then
      raise exception 'Informe o motivo da recusa com pelo menos 10 caracteres.' using errcode = '22023';
    end if;
    if char_length(btrim(p_reason)) > 2000 then
      raise exception 'O motivo da recusa deve ter no máximo 2000 caracteres.' using errcode = '22023';
    end if;

    update public.patient_health_plan_requests
    set status = 'rejected',
        reviewed_by = v_actor_id,
        reviewed_at = v_decided_at,
        rejection_reason = btrim(p_reason),
        coverage_start = null,
        coverage_end = null
    where id = v_request.id
    returning * into v_request;
  end if;

  return jsonb_build_object(
    'id', v_request.id,
    'status', v_request.status,
    'valid_until', v_request.coverage_end,
    'already_reviewed', false
  );
end;
$$;

-- A rotina privilegiada grava na tabela protegida, mas deriva o ator da sessão
-- e exige simultaneamente a permissão e um cargo oficial de nível 11–14.
create or replace function private.admin_set_patient_health_plan(
  p_patient_id bigint,
  p_valid_until date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action text;
  v_actor uuid := private.hpsm_current_actor();
  v_actor_name text;
  v_current public.patient_health_plan_requests%rowtype;
  v_end timestamptz;
  v_now timestamptz := now();
  v_request public.patient_health_plan_requests%rowtype;
  v_start timestamptz;
  v_today date := timezone('America/Sao_Paulo', now())::date;
begin
  if not private.has_permission(v_actor, 'healthplans.review')
     or coalesce(private.current_position_level(v_actor), 0) not between 11 and 14 then
    raise exception 'Somente os cargos 11 a 14 podem conceder ou ajustar o Plano de Saúde.' using errcode = '42501';
  end if;

  if p_patient_id is null or p_patient_id < 1 then
    raise exception 'Selecione um paciente válido.' using errcode = '22023';
  end if;
  if p_valid_until is null or p_valid_until < v_today or p_valid_until > v_today + 3650 then
    raise exception 'Informe uma data de vencimento entre hoje e os próximos 10 anos.' using errcode = '22023';
  end if;

  perform 1
  from public.patients patient
  where patient.id = p_patient_id
  for update;
  if not found then
    raise exception 'Paciente não localizado.' using errcode = 'P0002';
  end if;

  select request.*
  into v_current
  from public.patient_health_plan_requests request
  where request.patient_id = p_patient_id
    and request.status = 'approved'
  order by request.reviewed_at desc nulls last, request.id desc
  limit 1;

  v_action := case
    when v_current.id is not null and v_current.coverage_end > v_now then 'expiry_adjustment'
    else 'grant'
  end;

  if v_action = 'grant' and exists (
    select 1
    from public.patient_health_plan_requests pending
    where pending.patient_id = p_patient_id
      and pending.status = 'pending'
  ) then
    raise exception 'Este paciente possui uma solicitação aguardando confirmação. Analise a pendência antes de conceder o plano sem cobrança.' using errcode = 'P0001';
  end if;

  v_end := ((p_valid_until + 1)::timestamp at time zone 'America/Sao_Paulo') - interval '1 microsecond';
  v_start := case when v_action = 'expiry_adjustment' then v_current.coverage_start else v_now end;

  if v_end <= v_start then
    raise exception 'A data de vencimento deve ser posterior ao início da cobertura.' using errcode = '22023';
  end if;

  insert into public.patient_health_plan_requests (
    patient_id,
    attendance_id,
    status,
    requested_at,
    reviewed_by,
    reviewed_at,
    coverage_start,
    coverage_end,
    origin,
    administrative_action
  ) values (
    p_patient_id,
    null,
    'approved',
    v_now,
    v_actor,
    v_now,
    v_start,
    v_end,
    'administrative',
    v_action
  )
  returning * into v_request;

  select profile.display_name into v_actor_name
  from public.profiles profile
  where profile.user_id = v_actor;

  return jsonb_build_object(
    'id', v_request.id,
    'action', v_action,
    'status', 'active',
    'activated_at', v_request.coverage_start,
    'valid_until', v_request.coverage_end,
    'authorized_by', v_actor,
    'authorized_by_name', v_actor_name,
    'financial_value', 0
  );
end;
$$;

revoke all on function private.admin_set_patient_health_plan(bigint, date)
from public, anon, authenticated, service_role;
grant execute on function private.admin_set_patient_health_plan(bigint, date)
to authenticated;

create or replace function public.admin_set_patient_health_plan(
  p_patient_id bigint,
  p_valid_until date
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.admin_set_patient_health_plan(p_patient_id, p_valid_until);
$$;

revoke all on function public.admin_set_patient_health_plan(bigint, date)
from public, anon, authenticated, service_role;
grant execute on function public.admin_set_patient_health_plan(bigint, date)
to authenticated;

comment on function public.admin_set_patient_health_plan(bigint, date) is
  'Cargos oficiais 11–14 concedem ou ajustam a validade do plano sem criar venda, atendimento ou valor financeiro.';

-- Estado canônico: o último evento aprovado prevalece, inclusive quando a
-- Diretoria reduz uma validade que antes era maior.
create or replace function private.patient_portal_health_plan_state(p_patient_id bigint)
returns table (
  status text,
  activated_at timestamptz,
  valid_until timestamptz,
  pending_requested_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  with latest_approved as (
    select request.coverage_start, request.coverage_end
    from public.patient_health_plan_requests request
    where request.patient_id = p_patient_id
      and request.status = 'approved'
    order by request.reviewed_at desc nulls last, request.id desc
    limit 1
  ), latest_pending as (
    select request.requested_at
    from public.patient_health_plan_requests request
    where request.patient_id = p_patient_id
      and request.status = 'pending'
    order by request.requested_at, request.id
    limit 1
  )
  select
    case
      when approved.coverage_end > clock_timestamp() then 'active'
      when approved.coverage_end is not null then 'expired'
      when pending.requested_at is not null then 'awaiting_confirmation'
      else 'none'
    end,
    approved.coverage_start,
    approved.coverage_end,
    pending.requested_at
  from (select true) singleton
  left join latest_approved approved on true
  left join latest_pending pending on true;
$$;

create or replace view public.patient_directory
with (security_invoker = true)
as
select
  patient.id,
  patient.passport,
  patient.name,
  patient.phone,
  patient.emergency_contact_name,
  patient.emergency_contact_phone,
  patient.created_at,
  patient.updated_at,
  last_attendance.created_at as last_attendance_at,
  case
    when approved.coverage_end > now() then 'active'
    when approved.id is not null then 'expired'
    when pending.id is not null then 'awaiting_confirmation'
    else 'none'
  end as plan_status,
  approved.coverage_start as plan_activated_at,
  approved.coverage_end as plan_valid_until,
  approved.reviewed_by as plan_authorized_by,
  reviewer.display_name as plan_authorized_by_name,
  pending.id as pending_request_id,
  pending.requested_at as pending_requested_at,
  patient.birth_date
from public.patients patient
left join lateral (
  select attendance.created_at
  from public.attendances attendance
  where attendance.patient_id = patient.id
    and attendance.status = 'completed'
  order by attendance.created_at desc, attendance.id desc
  limit 1
) last_attendance on true
left join lateral (
  select request.id, request.coverage_start, request.coverage_end, request.reviewed_by
  from public.patient_health_plan_requests request
  where request.patient_id = patient.id
    and request.status = 'approved'
  order by request.reviewed_at desc nulls last, request.id desc
  limit 1
) approved on true
left join public.profiles reviewer on reviewer.user_id = approved.reviewed_by
left join lateral (
  select request.id, request.requested_at
  from public.patient_health_plan_requests request
  where request.patient_id = patient.id
    and request.status = 'pending'
  order by request.requested_at, request.id
  limit 1
) pending on true;

revoke all on public.patient_directory from public, anon, authenticated;
grant select on public.patient_directory to authenticated;

create or replace function public.hpsm_patient_quick_lookup(
  p_passport text,
  p_limit integer default 8
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[] := public.effective_permission_codes(v_actor);
  v_passport text := btrim(coalesce(p_passport, ''));
  v_limit integer := least(greatest(coalesce(p_limit, 8), 1), 8);
  v_result jsonb;
begin
  if not ('patients.view' = any(v_permissions)) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_passport !~ '^[0-9]{1,4}$' then
    raise exception 'Informe um passaporte válido.' using errcode = '22023';
  end if;

  with matching as materialized (
    select patient.id, patient.passport, patient.name, patient.phone, patient.birth_date,
      patient.emergency_contact_name, patient.emergency_contact_phone, patient.created_at, patient.updated_at
    from public.patients patient
    where patient.passport like v_passport || '%'
    order by (patient.passport = v_passport) desc, patient.passport
    limit v_limit
  ), plan_states as materialized (
    select matching.id as patient_id,
      case
        when approved.coverage_end > now() then 'active'
        when approved.id is not null then 'expired'
        when pending.id is not null then 'awaiting_confirmation'
        else 'none'
      end as status,
      approved.coverage_start as activated_at,
      approved.coverage_end as valid_until,
      approved.reviewed_by as authorized_by,
      reviewer.display_name as authorized_by_name,
      pending.id as pending_request_id,
      pending.requested_at as pending_requested_at
    from matching
    left join lateral (
      select request.id, request.coverage_start, request.coverage_end, request.reviewed_by
      from public.patient_health_plan_requests request
      where request.patient_id = matching.id
        and request.status = 'approved'
      order by request.reviewed_at desc nulls last, request.id desc
      limit 1
    ) approved on true
    left join public.profiles reviewer on reviewer.user_id = approved.reviewed_by
    left join lateral (
      select request.id, request.requested_at
      from public.patient_health_plan_requests request
      where request.patient_id = matching.id
        and request.status = 'pending'
      order by request.requested_at, request.id
      limit 1
    ) pending on true
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', matching.id,
    'passport', matching.passport,
    'name', matching.name,
    'phone', matching.phone,
    'birth_date', matching.birth_date,
    'emergency_contact_name', matching.emergency_contact_name,
    'emergency_contact_phone', matching.emergency_contact_phone,
    'created_at', matching.created_at,
    'updated_at', matching.updated_at,
    'health_plan', jsonb_build_object(
      'status', plan_states.status,
      'activated_at', plan_states.activated_at,
      'valid_until', plan_states.valid_until,
      'authorized_by', plan_states.authorized_by,
      'authorized_by_name', plan_states.authorized_by_name,
      'pending_request_id', plan_states.pending_request_id,
      'pending_requested_at', plan_states.pending_requested_at
    ),
    'partnerships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', partnership.id,
        'name', partnership.name,
        'status', partnership.status,
        'linked_at', membership.linked_at
      ) order by lower(partnership.name))
      from public.patient_partnerships membership
      join public.partnerships partnership
        on partnership.id = membership.partnership_id
       and partnership.status = 'active'
      where membership.patient_id = matching.id
        and membership.status = 'active'
    ), '[]'::jsonb)
  ) order by (matching.passport = v_passport) desc, matching.passport), '[]'::jsonb)
  into v_result
  from matching
  join plan_states on plan_states.patient_id = matching.id;

  return v_result;
end;
$$;

create or replace function public.patient_plan_history_page(
  p_patient_id bigint,
  p_limit integer default 10,
  p_offset integer default 0
)
returns table (total_count bigint, records jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.has_permission((select auth.uid()), 'patients.view') then
    raise exception 'Você não possui permissão para consultar pacientes.';
  end if;
  if p_limit < 1 or p_limit > 50 or p_offset < 0 then
    raise exception 'Paginação inválida.';
  end if;

  return query
  with matching as materialized (
    select request.*
    from public.patient_health_plan_requests request
    where request.patient_id = p_patient_id
  ), page as (
    select matching.*
    from matching
    order by matching.requested_at desc, matching.id desc
    limit p_limit offset p_offset
  ), rendered as (
    select
      page.requested_at,
      page.id,
      jsonb_build_object(
        'id', page.id,
        'attendance_id', page.attendance_id,
        'status', page.status,
        'requested_at', page.requested_at,
        'reviewed_at', page.reviewed_at,
        'rejection_reason', page.rejection_reason,
        'coverage_start', page.coverage_start,
        'coverage_end', page.coverage_end,
        'authorized_by_name', reviewer.display_name,
        'seller_name', seller.display_name,
        'seller_passport', seller.passport,
        'attendance_total', attendance.total,
        'origin', page.origin,
        'administrative_action', page.administrative_action,
        'plan_value', coalesce((
          select sum(item.line_total)
          from public.attendance_items item
          join public.service_catalog service on service.id = item.service_id
          where item.attendance_id = page.attendance_id
            and service.code = 'plano_saude_convenio'
        ), 0)
      ) as record
    from page
    left join public.attendances attendance on attendance.id = page.attendance_id
    left join public.profiles seller on seller.user_id = attendance.performed_by
    left join public.profiles reviewer on reviewer.user_id = page.reviewed_by
  )
  select
    (select count(*) from matching)::bigint,
    coalesce(jsonb_agg(rendered.record order by rendered.requested_at desc, rendered.id desc), '[]'::jsonb)
  from rendered;
end;
$$;

-- A timeline profissional não cria uma falsa solicitação financeira para o
-- evento administrativo e informa claramente se houve concessão ou ajuste.
create or replace function public.patient_timeline(p_patient_id bigint, p_limit integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Você não possui permissão para consultar pacientes.' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'Limite inválido.';
  end if;

  with events as (
    select
      'patient-created-' || patient.id::text as id,
      patient.created_at as event_at,
      'cadastro'::text as event_type,
      'Paciente cadastrado no HPSM'::text as title,
      'Passaporte ' || patient.passport as description,
      null::bigint as exam_id,
      null::bigint as cast_id
    from public.patients patient
    where patient.id = p_patient_id

    union all

    select
      'attendance-' || attendance.id::text,
      attendance.created_at,
      'attendance',
      case when attendance.status = 'cancelled' then 'Atendimento cancelado' else 'Atendimento realizado' end,
      coalesce(professional.display_name, 'Profissional') || ' · atendimento #' || attendance.id::text,
      null::bigint,
      null::bigint
    from public.attendances attendance
    left join public.profiles professional on professional.user_id = attendance.performed_by
    where attendance.patient_id = p_patient_id

    union all

    select
      'plan-request-' || request.id::text,
      request.requested_at,
      'health-plan-request',
      'Solicitação de Plano de Saúde registrada',
      'Atendimento #' || request.attendance_id::text || ' · aguardando conferência',
      null::bigint,
      null::bigint
    from public.patient_health_plan_requests request
    where request.patient_id = p_patient_id
      and request.origin = 'sale'

    union all

    select
      'plan-review-' || request.id::text,
      request.reviewed_at,
      'health-plan-review',
      case
        when request.status = 'rejected' then 'Ativação do plano recusada'
        when request.administrative_action = 'grant' then 'Plano de Saúde concedido sem cobrança'
        when request.administrative_action = 'expiry_adjustment' then 'Vencimento do Plano de Saúde ajustado'
        when request.coverage_start > request.reviewed_at + interval '1 minute' then 'Plano de Saúde renovado'
        else 'Plano de Saúde ativado'
      end,
      case
        when request.status = 'rejected' then coalesce(request.rejection_reason, 'Solicitação recusada')
        when request.origin = 'administrative' then 'Sem cobrança · validade até ' || to_char(request.coverage_end at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
        else 'Validade até ' || to_char(request.coverage_end at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
      end,
      null::bigint,
      null::bigint
    from public.patient_health_plan_requests request
    where request.patient_id = p_patient_id
      and request.status in ('approved', 'rejected')
      and request.reviewed_at is not null

    union all

    select
      'exam-requested-' || exam.id::text,
      exam.requested_at,
      'exam-requested',
      exam_type.name || ' solicitado',
      'Solicitado por ' || requester.display_name || coalesce(' · ' || requester_position.name, ''),
      exam.id,
      null::bigint
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    join public.profiles requester on requester.user_id = exam.requested_by
    left join public.staff_positions requester_position on requester_position.id = requester.position_id
    where exam.patient_id = p_patient_id
      and private.has_permission(v_actor, 'exams.view')

    union all

    select
      'exam-completed-' || exam.id::text,
      exam.completed_at,
      'exam-completed',
      exam_type.name || ' concluído',
      'Responsável: ' || responsible.display_name || coalesce(' · Revisor: ' || reviewer.display_name, ''),
      exam.id,
      null::bigint
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
    left join public.profiles reviewer on reviewer.user_id = exam.reviewed_by
    where exam.patient_id = p_patient_id
      and exam.status = 'completed'
      and exam.completed_at is not null
      and private.has_permission(v_actor, 'exams.view')

    union all

    select
      'cast-applied-' || cast_record.id::text,
      cast_record.applied_at,
      'cast-applied',
      'Gesso aplicado — ' || private.clinical_cast_location_label(cast_record.body_region, cast_record.laterality),
      'Profissional: ' || applied.display_name
        || coalesce(' · ' || applied_position.name, '')
        || coalesce(' · Atendimento #' || cast_record.attendance_id::text, ''),
      null::bigint,
      cast_record.id
    from public.clinical_casts cast_record
    join public.profiles applied on applied.user_id = cast_record.applied_by
    left join public.staff_positions applied_position on applied_position.id = applied.position_id
    where cast_record.patient_id = p_patient_id
      and private.has_permission(v_actor, 'casts.view')

    union all

    select
      'cast-forecast-' || audit.id::text,
      audit.created_at,
      'cast-forecast-changed',
      'Previsão de retirada do gesso alterada',
      'De ' || to_char((audit.old_values->>'expected_removal_at')::timestamptz at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
        || ' para ' || to_char((audit.new_values->>'expected_removal_at')::timestamptz at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
        || ' · Responsável: ' || coalesce(actor.display_name, 'Profissional'),
      null::bigint,
      cast_record.id
    from public.audit_logs audit
    join public.clinical_casts cast_record on cast_record.id::text = audit.entity_id
    left join public.profiles actor on actor.user_id = audit.actor_user_id
    where audit.entity_name = 'clinical_casts'
      and audit.action = 'CAST_EXPECTED_REMOVAL_CHANGED'
      and audit.old_values ? 'expected_removal_at'
      and audit.new_values ? 'expected_removal_at'
      and cast_record.patient_id = p_patient_id
      and private.has_permission(v_actor, 'casts.view')

    union all

    select
      'cast-removed-' || cast_record.id::text,
      cast_record.removed_at,
      'cast-removed',
      'Gesso retirado — ' || private.clinical_cast_location_label(cast_record.body_region, cast_record.laterality),
      'Profissional: ' || removed.display_name
        || coalesce(' · ' || removed_position.name, '')
        || coalesce(' · ' || cast_record.removal_notes, ''),
      null::bigint,
      cast_record.id
    from public.clinical_casts cast_record
    join public.profiles removed on removed.user_id = cast_record.removed_by
    left join public.staff_positions removed_position on removed_position.id = removed.position_id
    where cast_record.patient_id = p_patient_id
      and cast_record.status = 'removed'
      and cast_record.removed_at is not null
      and private.has_permission(v_actor, 'casts.view')

    union all

    select
      'cast-cancelled-' || cast_record.id::text,
      cast_record.cancelled_at,
      'cast-cancelled',
      'Registro de gesso cancelado',
      private.clinical_cast_location_label(cast_record.body_region, cast_record.laterality)
        || coalesce(' · Motivo: ' || cast_record.cancellation_reason, '')
        || ' · Responsável: ' || cancelled.display_name,
      null::bigint,
      cast_record.id
    from public.clinical_casts cast_record
    join public.profiles cancelled on cancelled.user_id = cast_record.cancelled_by
    where cast_record.patient_id = p_patient_id
      and cast_record.status = 'cancelled'
      and cast_record.cancelled_at is not null
      and private.has_permission(v_actor, 'casts.view')
  ), limited as (
    select *
    from events
    where event_at is not null
    order by event_at desc, id desc
    limit p_limit
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', limited.id,
      'date', limited.event_at,
      'type', limited.event_type,
      'title', limited.title,
      'description', limited.description,
      'exam_id', limited.exam_id,
      'cast_id', limited.cast_id
    ) order by limited.event_at desc, limited.id desc
  ), '[]'::jsonb)
  into v_result
  from limited;

  return v_result;
end;
$$;

revoke all on function public.admin_set_patient_health_plan(bigint, date)
from public, anon, authenticated, service_role;
grant execute on function public.admin_set_patient_health_plan(bigint, date)
to authenticated;

notify pgrst, 'reload schema';

-- HPSM pós-1.0 — limites por item e benefício no atendimento atual.
-- Não cria estoque, saldo, limite histórico ou alteração retroativa.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.attendance_item_limit(
  p_service_code text,
  p_benefit_code text
)
returns integer
language sql
immutable
security invoker
set search_path = ''
as $$
  select case lower(btrim(coalesce(p_service_code, '')))
    when 'kitmed' then 2
    when 'bandagem' then 5
    when 'atadura' then case
      when p_benefit_code = 'policiais_arcanjos' then 20
      when p_benefit_code in ('parceiros_hp', 'plano_saude') then 15
      else 10
    end
    when 'analgesico' then case
      when p_benefit_code in ('parceiros_hp', 'plano_saude') then 15
      else 10
    end
    when 'ritmoneury' then 5
    when 'sinkalmy' then 5
    when 'adrenalina' then case
      when p_benefit_code in ('policiais_arcanjos', 'parceiros_hp', 'plano_saude') then 5
      else 3
    end
    else null
  end;
$$;

revoke all on function private.attendance_item_limit(text, text)
from public, anon, authenticated, service_role;
grant execute on function private.attendance_item_limit(text, text) to service_role;

create or replace function private.create_attendance(
  p_patient_id bigint,
  p_items jsonb,
  p_notes text default null,
  p_benefit_code text default null,
  p_partnership_id bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attendance_id bigint;
  v_discount numeric(18, 2);
  v_input_count integer;
  v_limit integer;
  v_limited_item_name text;
  v_patient_name text;
  v_patient_passport text;
  v_plan_code text;
  v_plan_name text;
  v_partnership_name text;
  v_subtotal numeric(18, 2);
  v_valid_count integer;
  v_priced_items jsonb;
begin
  perform private.hpsm_current_actor();
  if not private.has_permission((select auth.uid()), 'attendances.create') then
    raise exception 'Você não possui permissão para registrar atendimentos.';
  end if;

  if p_patient_id is null then
    v_patient_name := 'Venda avulsa';
    v_patient_passport := '—';
  else
    select patient.name, patient.passport into v_patient_name, v_patient_passport
    from public.patients patient where patient.id = p_patient_id;
    if not found then raise exception 'Paciente não localizado.'; end if;
  end if;

  v_plan_code := nullif(btrim(coalesce(p_benefit_code, '')), '');
  if v_plan_code is not null then
    select plan.name into v_plan_name from public.benefit_plans plan where plan.code = v_plan_code;
    if not found then raise exception 'Benefício inválido ou indisponível.'; end if;
  end if;

  if v_plan_code = 'parceiros_hp' then
    if p_patient_id is null or p_partnership_id is null then
      raise exception 'Selecione a parceria responsável por este benefício.' using errcode = '22023';
    end if;
    select partnership.name into v_partnership_name
    from public.partnerships partnership
    join public.patient_partnerships membership
      on membership.partnership_id = partnership.id
     and membership.patient_id = p_patient_id
     and membership.status = 'active'
    where partnership.id = p_partnership_id and partnership.status = 'active';
    if not found then
      raise exception 'O paciente não possui vínculo ativo com a parceria selecionada.' using errcode = '22023';
    end if;
  elsif p_partnership_id is not null then
    raise exception 'A parceria só pode ser informada com o benefício Parceiro do HP.' using errcode = '22023';
  end if;

  if p_notes is not null and char_length(p_notes) > 1000 then raise exception 'Observação muito longa.'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'Inclua ao menos um item.'; end if;
  v_input_count := jsonb_array_length(p_items);
  if v_input_count < 1 or v_input_count > 50 then raise exception 'Quantidade de itens inválida.'; end if;
  if exists (select 1 from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer) group by service_id having count(*) <> 1) then
    raise exception 'Cada item deve aparecer apenas uma vez.';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
    join public.service_catalog catalog on catalog.id = item.service_id
    where catalog.code = 'plano_saude_convenio' and item.quantity <> 1
  ) then raise exception 'O plano de saúde pode aparecer somente uma vez no atendimento.'; end if;
  if p_patient_id is null and exists (
    select 1 from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
    join public.service_catalog catalog on catalog.id = item.service_id
    where lower(btrim(catalog.category)) not in ('insumos', 'medicamentos')
  ) then raise exception 'Venda avulsa aceita somente insumos e medicamentos.'; end if;
  if not private.has_permission((select auth.uid()), 'catalog.view')
     or (p_patient_id is not null and not private.has_permission((select auth.uid()), 'patients.view')) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  perform 1 from public.service_catalog where id in (
    select service_id from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
  ) for share;
  perform 1 from public.plan_discounts where plan_code = v_plan_code and service_id in (
    select service_id from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
  ) for share;

  select catalog.name, private.attendance_item_limit(catalog.code, v_plan_code)
  into v_limited_item_name, v_limit
  from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
  join public.service_catalog catalog on catalog.id = item.service_id
  where private.attendance_item_limit(catalog.code, v_plan_code) is not null
    and item.quantity > private.attendance_item_limit(catalog.code, v_plan_code)
  order by catalog.id
  limit 1;
  if found then
    raise exception 'Quantidade de % acima do limite permitido para este atendimento.', v_limited_item_name
      using errcode = '22023', hint = format('O máximo permitido é %s.', v_limit);
  end if;

  with input_items as (
    select service_id, quantity from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
  )
  select count(*), coalesce(sum(catalog.unit_price * input_items.quantity), 0),
    coalesce(sum(round(catalog.unit_price * input_items.quantity * coalesce(discount.discount_percent, 0) / 100, 2)), 0),
    coalesce(jsonb_agg(jsonb_build_object(
      'service_id', catalog.id, 'service_name', catalog.name, 'unit_price', catalog.unit_price,
      'quantity', input_items.quantity, 'discount_percent', coalesce(discount.discount_percent, 0)
    )), '[]'::jsonb)
  into v_valid_count, v_subtotal, v_discount, v_priced_items
  from input_items
  join public.service_catalog catalog on catalog.id = input_items.service_id and catalog.active
  left join public.plan_discounts discount on discount.service_id = catalog.id and discount.plan_code = v_plan_code
  where input_items.quantity between 1 and 99;
  if v_valid_count <> v_input_count then raise exception 'Um dos itens não está disponível.'; end if;

  insert into public.attendances (
    patient_id, patient_name, patient_passport, plan_code, plan_name, partnership_id, partnership_name,
    subtotal, discount, notes, performed_by
  ) values (
    p_patient_id, v_patient_name, v_patient_passport, v_plan_code, v_plan_name, p_partnership_id, v_partnership_name,
    v_subtotal, v_discount, nullif(btrim(coalesce(p_notes, '')), ''), (select auth.uid())
  ) returning id into v_attendance_id;

  insert into public.attendance_items (attendance_id, service_id, service_name, unit_price, quantity, discount_percent)
  select v_attendance_id, priced.service_id, priced.service_name, priced.unit_price, priced.quantity, priced.discount_percent
  from jsonb_to_recordset(v_priced_items) priced(
    service_id bigint, service_name text, unit_price numeric, quantity smallint, discount_percent numeric
  );
  return v_attendance_id;
end;
$$;

revoke all on function private.create_attendance(bigint, jsonb, text, text, bigint)
from public, anon, authenticated, service_role;
grant execute on function private.create_attendance(bigint, jsonb, text, text, bigint)
to authenticated, service_role;


