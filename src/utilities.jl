_incomplete_job(job) = !(job["status"] in ["SUCCEEDED", "FAILED"])
_suffix_asterisk(prefix) = endswith(prefix, "*") ? prefix : string(prefix, "*")

function _get_job_ids(job_queue, prefix)
    # Check if the prefix provided ends w/ '*", if not append it
    prefix = _suffix_asterisk(prefix)

    resp = @mock Batch.list_jobs(
        Dict(
            "jobQueue" => job_queue,
            "filters" => [Dict("name" => "JOB_NAME", "values" => [prefix])],
        ),
    )
    jobs = resp["jobSummaryList"]

    while haskey(resp, "nextToken")
        resp = @mock Batch.list_jobs(
            Dict("jobQueue" => job_queue, "nextToken" => resp["nextToken"])
        )
        append!(jobs, resp["jobSummaryList"])
    end

    filter!(j -> _incomplete_job(j), jobs)

    return [j["jobId"] for j in jobs]
end

"""
    terminate_jobs()

Terminate all Batch jobs with a given prefix.

# Arguments
- `job_queue::JobQueue`: JobQueue where the jobs reside
- `prefix::AbstractString`: Prefix for the jobs

# Keywords
- `reason::AbstractString=""`: Reason to terminate the jobs

# Return
- `Array{String}`: Terminated Job Ids
"""
function terminate_jobs(
    job_queue::AbstractString, prefix::AbstractString; reason::AbstractString=""
)
    job_ids = _get_job_ids(job_queue, prefix)

    for job_id in job_ids
        @mock Batch.terminate_job(job_id, reason)
    end

    return job_ids
end

function terminate_jobs(
    job_queue::JobQueue, prefix::AbstractString; reason::AbstractString=""
)
    return terminate_jobs(job_queue.arn, prefix; reason=reason)
end
