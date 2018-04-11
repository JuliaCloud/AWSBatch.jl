using AWSBatch: JobState, SUBMITTED, PENDING, RUNNABLE, STARTING, RUNNING, SUCCEEDED, FAILED

@testset "JobState" begin
    @testset "parse" begin
        @test length(instances(JobState)) == 7
        @test parse(JobState, "SUBMITTED") == SUBMITTED
        @test parse(JobState, "PENDING") == PENDING
        @test parse(JobState, "RUNNABLE") == RUNNABLE
        @test parse(JobState, "STARTING") == STARTING
        @test parse(JobState, "RUNNING") == RUNNING
        @test parse(JobState, "SUCCEEDED") == SUCCEEDED
        @test parse(JobState, "FAILED") == FAILED
    end

    @testset "order" begin
        @test SUBMITTED < PENDING < RUNNABLE < STARTING < RUNNING < SUCCEEDED < FAILED
    end
end
