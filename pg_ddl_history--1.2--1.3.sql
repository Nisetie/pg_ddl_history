\echo Use "CREATE EXTENSION pg_ddl_history" to load this file! \quit

CREATE OR REPLACE FUNCTION changes.ddl_drop_catch()
    RETURNS event_trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF SECURITY DEFINER
AS $BODY$
declare
	ddl_r record;
	details jsonb;
begin
	for ddl_r in (select distinct on (object_identity) * from pg_event_trigger_dropped_objects()) loop	
	
		continue when ddl_r.is_temporary = true;

		details = '{}'::jsonb;	
		details = details || jsonb_build_object('classid',ddl_r.classid);
		details = details || jsonb_build_object('objid',ddl_r.objid);
		details = details || jsonb_build_object('objsubid',ddl_r.objsubid);
		details = details || jsonb_build_object('object_type',ddl_r.object_type);		
		details = details || jsonb_build_object('schema_name',ddl_r.schema_name);
		details = details || jsonb_build_object('object_name',ddl_r.object_name);
		details = details || jsonb_build_object('object_identity',ddl_r.object_identity);
		details = details || jsonb_build_object('TG_TAG',TG_TAG);
		details = details || jsonb_build_object('session_user',session_user);
		details = details || jsonb_build_object('inet_client_addr',inet_client_addr());
		details = details || jsonb_build_object('pg_backend_pid',pg_backend_pid());

		insert into changes.history(cmd,"timestamp", details)
		select 
			current_query()
			,now()
			,details;
		
	end loop;
end;
$BODY$;