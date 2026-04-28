\echo Use "CREATE EXTENSION pg_ddl_history" to load this file! \quit

COMMENT ON EXTENSION pg_ddl_history IS 'Журналирование DDL-команд';

create schema changes;

create table changes.version (
	id bigint primary key generated always as identity,
	fixed timestamptz,
	commentary text
);

create table changes.history(
	id bigint primary key generated always as identity,
	version_id bigint references changes.version(id),
	"timestamp" timestamptz,
	details jsonb,	
	cmd text
);

CREATE OR REPLACE PROCEDURE changes.checkpoint(IN commentary text DEFAULT ''::text)
LANGUAGE 'plpgsql'
AS $BODY$
	<<local>>
	declare
		_ts timestamptz = now();
		_version_id bigint;
	begin			
		insert into changes.version(fixed,commentary) 
		select _ts, checkpoint.commentary
		returning id into strict local._version_id;		
		
		update changes.history
		set version_id = local._version_id
		where version_id is null;
	end;
$BODY$;

create or replace function changes.ddl_change_catch() returns event_trigger
language plpgsql 
security definer
as $$
declare
	ddl_r record;
	details jsonb;
	ddl_count int = 0;
begin
		for ddl_r in (select * from pg_event_trigger_ddl_commands() limit 1) loop	

			details = '{}'::jsonb;
		
			--не логировать работу с временными таблицами
			if (ddl_r.object_type = 'table' and (select relpersistence from pg_class where oid = ddl_r.objid) = 't') then
				return;
			end if;
			details = details || jsonb_build_object('classid',ddl_r.classid);
			details = details || jsonb_build_object('objid',ddl_r.objid);
			details = details || jsonb_build_object('objsubid',ddl_r.objsubid);
			details = details || jsonb_build_object('command_tag',ddl_r.command_tag);
			details = details || jsonb_build_object('object_type',ddl_r.object_type);		
			details = details || jsonb_build_object('schema_name',ddl_r.schema_name);
			details = details || jsonb_build_object('object_identity',ddl_r.object_identity);
			details = details || jsonb_build_object('in_extension',ddl_r.in_extension);
			details = details || jsonb_build_object('session_user',session_user);

			insert into changes.history(cmd,"timestamp", details)
			select 
				(select query from pg_stat_activity where pid = pg_backend_pid())
				,now()
				,details;

			ddl_count = ddl_count + 1;
			
		end loop;
		
		if ddl_count = 0 then
			details = '{}'::jsonb;
			details = details || jsonb_build_object('session_user',session_user);
			insert into changes.history(cmd,"timestamp", details)
			select 
				(select query from pg_stat_activity where pid = pg_backend_pid())
				,now()
				,details;		
		end if;
end;
$$;

create view changes.v_fixed_history
as
select v.id, v.fixed, string_agg(cmd,E'\r\n' order by timestamp desc) 
from changes.history h 
join changes.version v on h.version_id = v.id
where version_id is not null
group by v.id, v.fixed;

grant usage on schema changes to public;
grant select on changes.history to public;
grant select on changes.version to public;
grant select on changes.v_fixed_history to public;
grant execute on function changes.ddl_change_catch to public;

create event trigger ddl_after on ddl_command_end execute function changes.ddl_change_catch();