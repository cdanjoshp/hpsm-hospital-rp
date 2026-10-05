-- Evita conversão de path arbitrário antes de confirmar que o segmento do exame é numérico.

drop policy if exists clinical_exam_images_storage_insert on storage.objects;
create policy clinical_exam_images_storage_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'clinical-exam-images'
  and (storage.foldername(name))[1] = 'clinical-exams'
  and exists (
    select 1 from public.clinical_exams exam
    where exam.id = case
        when coalesce((storage.foldername(name))[2] ~ '^[0-9]+$', false)
          then ((storage.foldername(name))[2])::bigint
        else null
      end
      and exam.status = 'in_progress'
      and (
        (exam.responsible_professional_id = (select auth.uid()) and private.has_permission((select auth.uid()), 'exams.perform'))
        or private.has_permission((select auth.uid()), 'exams.review')
      )
  )
);

drop policy if exists clinical_exam_images_storage_delete on storage.objects;
create policy clinical_exam_images_storage_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'clinical-exam-images'
  and (storage.foldername(name))[1] = 'clinical-exams'
  and exists (
    select 1 from public.clinical_exams exam
    where exam.id = case
        when coalesce((storage.foldername(name))[2] ~ '^[0-9]+$', false)
          then ((storage.foldername(name))[2])::bigint
        else null
      end
      and exam.status = 'in_progress'
      and (
        (exam.responsible_professional_id = (select auth.uid()) and private.has_permission((select auth.uid()), 'exams.perform'))
        or private.has_permission((select auth.uid()), 'exams.review')
      )
  )
);

notify pgrst, 'reload schema';
