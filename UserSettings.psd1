# You can edit this file using the ConfigData commands: Get-ConfigData and Set-ConfigData
# For a list of valid {SpecialFolder} tokens, run Get-SpecialFolder
# Note that the defaults here are the ones recommended by Microsoft:
# http://msdn.microsoft.com/en-us/library/windows/desktop/dd878350%28v=vs.85%29.aspx
@{ 
   InstallPaths = @{
      CommonPath = "{ProgramFiles}\WindowsPowerShell\Modules"
      UserPath = "{MyDocuments}\WindowsPowerShell\Modules"
   }
   Repositories = @{
      # The file-based repository needs to be a url or something we can update
      FileSystem = "PoshCodeRegistry", "\\PoshCode.org\Modules"
      # GitHub = "https://api.github.com/search/code"
   }
}