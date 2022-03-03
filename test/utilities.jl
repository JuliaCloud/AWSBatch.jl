list_jobs_patch = @patch function AWSBatch.Batch.list_jobs(params)
    response = Dict{String,Any}(
        "jobSummaryList" => [
            Dict("jobId" => "1", "status" => "SUCCEEDED"),
            Dict("jobId" => "2", "status" => "FAILED"),
            Dict("jobId" => "3", "status" => "RUNNABLE"),
        ],
    )

    if !haskey(params, "nextToken")
        response["nextToken"] = "nextToken"
    end

    return response
end

terminate_job_patch = @patch AWSBatch.Batch.terminate_job(a...) = Dict()

@testset "_incomplete_job" begin
    @test_throws KeyError AWSBatch._incomplete_job(Dict())
    @test !AWSBatch._incomplete_job(Dict("status" => "SUCCEEDED"))
    @test !AWSBatch._incomplete_job(Dict("status" => "FAILED"))
    @test AWSBatch._incomplete_job(Dict("status" => "FOOBAR"))
end

@testset "_suffix_asterisk" begin
    @test AWSBatch._suffix_asterisk("foobar") == "foobar*"
    @test AWSBatch._suffix_asterisk("foobar*") == "foobar*"
end

@testset "_get_job_ids" begin
    apply(list_jobs_patch) do
        response = AWSBatch._get_job_ids("foo", "bar")
        @test response == ["3", "3"]
    end
end

@testset "terminate_jobs" begin
    apply([list_jobs_patch, terminate_job_patch]) do
        response = terminate_jobs("foo", "bar")
        @test response == ["3", "3"]
    end
end
