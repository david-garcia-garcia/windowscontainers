Describe 'compose-async.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        docker compose -f servercore2022/compose-async.yaml up -d;
        WaitForLog "servercore2022-servercore-1" "Initialization Completed"  -extendedTimeout
    }

    It 'Booted asynchronously' {
        WaitForLog "servercore2022-servercore-1" "init scripts asynchronously"
    }

    It 'Executed 0001_SetShutdownTimeout.ps1' {
        WaitForLog "servercore2022-servercore-1" "0001_SetShutdownTimeout.ps1: START"
        WaitForLog "servercore2022-servercore-1" "0001_SetShutdownTimeout.ps1: END"
    }

    It 'Executed 0300_StartServices.ps1' {
        WaitForLog "servercore2022-servercore-1" "0300_StartServices.ps1: START"
        WaitForLog "servercore2022-servercore-1" "0300_StartServices.ps1: END"
    }

    It 'Executed 0999_ConfigureScheduledTasks.ps1' {
        WaitForLog "servercore2022-servercore-1" "0999_ConfigureScheduledTasks.ps1: START"
        WaitForLog "servercore2022-servercore-1" "0999_ConfigureScheduledTasks.ps1: END"
    }

    AfterAll {
        docker compose -f servercore2022/compose-async.yaml down;
    }
}

