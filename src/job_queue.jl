using AWSSDK.Batch: describe_job_queues

struct JobQueue
    arn::String

    function JobQueue(queue::AbstractString)
        arn = job_queue_arn(queue)
        arn === nothing && error("No job queue ARN found for: $queue")
        new(arn)
    end
end

Base.:(==)(a::JobQueue, b::JobQueue) = a.arn == b.arn

describe(queue::JobQueue) = describe_job_queue(queue)
max_vcpus(queue::JobQueue) = sum(max_vcpus(ce) for ce in compute_environments(queue))

function compute_environments(queue::JobQueue)
    ce_order = describe(queue)["computeEnvironmentOrder"]

    compute_envs = Vector{ComputeEnvironment}(undef, length(ce_order))
    for ce in ce_order
        i, arn = ce["order"], ce["computeEnvironment"]
        compute_envs[i] = ComputeEnvironment(arn)
    end

    return compute_envs
end

function job_queue_arn(queue::AbstractString)
    startswith(queue, "arn:") && return queue
    json = describe_job_queue(queue)
    isempty(json) ? nothing : json["jobQueueArn"]
end

describe_job_queue(queue::JobQueue) = describe_job_queue(queue.arn)

function describe_job_queue(queue::AbstractString)::OrderedDict
    json = @mock describe_job_queues(Dict("jobQueues" => [queue]))
    queues = json["jobQueues"]
    len = length(queues)::Int
    @assert len <= 1
    return len == 1 ? first(queues) : OrderedDict()
end
