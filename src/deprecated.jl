using Base: @deprecate

@deprecate logs(job::BatchJob) [Dict("eventId" => e.id, "ingestionTime" => e.ingestion_time, "timestamp" => e.timestamp, "message" => e.message) for e in log_events(job)]
@deprecate BatchStatus JobState

@deprecate BatchJob(; kwargs...) run_batch(; filter((x)->(x[1] != :id), kwargs)...)  # id is no longer a valid kwarg
@deprecate submit!(job::BatchJob) job  # Creating BatchJob's now automatically submits the job and submit doesn't need to be explicitly called
@deprecate job_definition_arn(job::BatchJob) job_definition_arn(JobDefinition(describe(job)["jobDefinition"]))

# Deprecate methods that now are called explicitly on JobDefinition's and not on BatchJob's
@deprecate isregistered(job::BatchJob) isregistered(JobDefinition(describe(job)["jobDefinition"]))
@deprecate register!(job::BatchJob) JobDefinition(describe(job)["jobDefinition"])  # Job definition should already be registered for a created BatchJob, so just look it up
@deprecate deregister!(job::BatchJob) deregister(JobDefinition(describe(job)["jobDefinition"]))

@deprecate register(job_definition::JobDefinition) register(job_definition.name)

