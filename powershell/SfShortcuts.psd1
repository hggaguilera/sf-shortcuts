@{
    RootModule           = 'SfShortcuts.psm1'
    ModuleVersion        = '3.1.0'
    GUID                 = 'ac4cc4ab-28e6-4a50-afaa-5446aaa1f25a'
    Author               = 'Hector Gonzalez'
    Description          = 'Short, predictable commands for the Salesforce CLI (sf), with tab completion for your classes, components and orgs.'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'sfdobj', 'sfdfields', 'sfdcls', 'sfdtrg', 'sfdlwc', 'sfdaura', 'sfdvf', 'sfdflow', 'sfdlayout',
        'sfdperm', 'sfdmdt', 'sfdlabels', 'sfdmeta', 'sfdbranch', 'sfdcheck', 'sfdpreview',
        'sfrobj', 'sfrcls', 'sfrlwc', 'sfrmeta',
        'sftest', 'sftestm', 'sftestall', 'sfapex', 'sfq',
        'sflogs', 'sfopen', 'sfwho', 'sforgs', 'sfdefault', 'sfhelp'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('Salesforce', 'sf', 'sfdx', 'cli', 'apex', 'lwc', 'deploy', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            LicenseUri = 'https://github.com/hggaguilera/sf-shortcuts/blob/main/LICENSE'
            ProjectUri = 'https://github.com/hggaguilera/sf-shortcuts'
        }
    }
}
