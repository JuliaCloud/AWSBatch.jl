using Base: @deprecate

@deprecate logs(job::BatchJob) [Dict("eventId" => e.id, "ingestionTime" => e.ingestion_time, "timestamp" => e.timestamp, "message" => e.message) for e in log_events(job)]
@deprecate BatchStatus JobState

@deprecate BatchJob(; id=id, kwargs...) BatchJob(id)
@deprecate submit!(job::BatchJob) submit
@deprecate job_definition_arn(job::BatchJob) job_definition_arn(JobDefinition(job))

# Deprecate methods that now are called explicitly on JobDefinition's and not on BatchJob's
@deprecate isregistered(job::BatchJob) isregistered(JobDefinition(job))
@deprecate register!(job::BatchJob) register
@deprecate deregister!(job::BatchJob) deregister(JobDefinition(job))

@deprecate register(job_definition::JobDefinition) register(job_definition.name)

