using Base: @deprecate

@deprecate logs(job::BatchJob) [Dict("eventId" => e.id, "ingestionTime" => e.ingestion_time, "timestamp" => e.timestamp, "message" => e.message) for e in log_events(job)]
@deprecate BatchStatus JobState

@deprecate submit!(job::BatchJob) error("`submit!(job::BatchJob)` is no longer supported. Look at `submit` or `run_batch` to submit batch jobs")
@deprecate job_definition_arn(job::BatchJob) job_definition_arn(JobDefinition(job))

# Deprecate methods that now are called explicitly on JobDefinition's and not on BatchJob's
@deprecate isregistered(job::BatchJob) isregistered(JobDefinition(job))
@deprecate register!(job::BatchJob) error("`register`!(job::BatchJob)` is no longer supported. Look at `register` to register job definitions")
@deprecate deregister!(job::BatchJob) error("`deregister`!(job::BatchJob)` is no longer supported. Look at `deregister` to de-register job definitions")

@deprecate register(job_definition::JobDefinition) register(job_definition.name)

function BatchJob(; id="", kwargs...)
    if !isempty(id) && isempty(kwargs)
        Base.depwarn("BatchJob(; id=id)` is deprecated, use `BatchJob(id)` instead", :BatchJob)
        BatchJob(id)
    elseif isempty(id) && !isempty(kwargs)
        Base.depwarn("`BatchJob(; kwargs...)` is deprecated, use `run_batch(; kwargs...)` instead", :BatchJob)
        run_batch(; kwargs...)
    else
        Base.depwarn("`BatchJob(; id=id, kwargs...)` is deprecated, ignoring `id` and using `run_batch(; kwargs...)` instead", :BatchJob)
        run_batch(; kwargs...)
    end
end
