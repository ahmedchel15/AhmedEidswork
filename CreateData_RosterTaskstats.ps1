$logFolderPath = "R:\Customers\11624H\logs\SRVKOEV020838\rosterstats"
$logFiles = Get-ChildItem -Path $logFolderPath -File | Select-Object -First 500

$taskData = @{}

foreach ($logFile in $logFiles) {
    Write-Host "Processing $($logFile.FullName)"

    $logContent = Get-Content -Path $logFile.FullName -Raw | ConvertFrom-Json
    $taskArray = $logContent.allTasks

    $creationDate = $logFile.CreationTime.ToString("yyyy-MM-dd")
   
    
    if (-not $taskData.ContainsKey($creationDate)) {
        $taskData[$creationDate] = @{
            
            TotalTasks = 0
            DistinctTasks = @{}
        }
    }
    
    foreach ($task in $taskArray) {
        $taskId = $task.TaskId
        $taskName = $task.TaskName
        $statusProgress = $task.StatusProgress

        $status = if ($statusProgress -eq 100) { "Completed" } else { "Running" }

    $interval =$logFile.LastWriteTime.ToString("yyyy-MM-dd hh:mm")

        if (-not $taskData[$creationDate].DistinctTasks.ContainsKey($taskId)) {
            $taskData[$creationDate].DistinctTasks[$taskId] = @{
                TaskId = $taskId
                TaskName = $taskName
                Type = $task.TaskType
                CompletedCount = 0
                RunningCount = 0
                Intervals = @{}
            }
        }

        if (-not $taskData[$creationDate].DistinctTasks[$taskId].Intervals.ContainsKey($interval)) {
            $taskData[$creationDate].DistinctTasks[$taskId].Intervals[$interval] = @{
                Completed = 0
                Running = 0
            }
        }

        if ($status -eq "Completed") {
            $taskData[$creationDate].DistinctTasks[$taskId].CompletedCount++

        } else {
            $taskData[$creationDate].DistinctTasks[$taskId].RunningCount++

        }
        
        $taskData[$creationDate].TotalTasks++ 
    }

}  



$taskCsvOutput = @()
$distinctTaskCsvOutput = @()

foreach ($date in $taskData.Keys) {
    $dateInfo = $taskData[$date]

    foreach ($taskId in $dateInfo.DistinctTasks.Keys) {
        $taskInfo = $dateInfo.DistinctTasks[$taskId]
        
        foreach ($interval in $taskInfo.Intervals.Keys) {
            $intervalData = $taskInfo.Intervals[$interval]
            
          
            
            $taskCsvOutput += [PSCustomObject]@{
                dateinterval = $interval
                TaskId = $taskInfo.TaskId
                TaskName = $taskInfo.TaskName
                Type = $taskInfo.Type
                Completed = $taskInfo.CompletedCount
                Running = $taskInfo.RunningCount
                TotalTasks = $dateInfo.TotalTasks
            }
        }
        
        $distinctTaskCsvOutput += [PSCustomObject]@{
            Date = $date
            TaskId = $taskInfo.TaskId
            TaskName = $taskInfo.TaskName
            Type = $taskInfo.Type
            Completed = $taskInfo.CompletedCount
            Running = $taskInfo.RunningCount
            TotalTasks = $dateInfo.TotalTasks
        }
    }
}

$distinctTaskOutputPath = "C:\Users\aeid\Documents\Metrics\distinct_task_data.csv"
$distinctTaskCsvOutput | Export-Csv -Path $distinctTaskOutputPath -NoTypeInformation
Write-Host "CSV export for distinct tasks completed successfully to $distinctTaskOutputPath"

$taskOutputPath = "C:\Users\aeid\Documents\Metrics\task_data.csv"
$taskCsvOutput | Export-Csv -Path $taskOutputPath -NoTypeInformation
Write-Host "CSV export for tasks completed successfully to $taskOutputPath"
