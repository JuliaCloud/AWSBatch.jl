using Base: @deprecate

@deprecate logs(job::BatchJob) [Dict("eventId" => e.id, "ingestionTime" => e.ingestion_time, "timestamp" => e.timestamp, "message" => e.message) for e in log_events(job)]
