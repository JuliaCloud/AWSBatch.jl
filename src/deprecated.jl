using Base: @deprecate

@deprecate logs(job::BatchJob) [Dict("eventId" => e.event_id, "ingestionTime" => e.ingestion_time, "timestamp" => e.timestamp, "message" => e.message) for e in log_events(job)]
