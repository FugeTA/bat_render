# ================================================================
# husk_utils.Tests.ps1
# husk_utils.psm1 のテストスイート (Pester v3互換)
# ================================================================

# テスト対象モジュールをインポート
$modulePath = Join-Path $PSScriptRoot "husk_utils.psm1"
Import-Module $modulePath -Force

# テストフィクスチャのパス
$script:fixtureDir = Join-Path $PSScriptRoot "test_fixtures"

Describe "husk_utils Module Tests" {
    
    Context "Resolve-UsdPath" {
        It "normalizes existing file path" {
            $testFile = $PSCommandPath
            $result = Resolve-UsdPath $testFile
            $result | Should Not BeNullOrEmpty
            $result | Should Match "husk_utils\.Tests\.ps1"
        }
        
        It "normalizes existing folder path" {
            $result = Resolve-UsdPath $PSScriptRoot
            $result | Should Not BeNullOrEmpty
            $result | Should Be $PSScriptRoot
        }
        
        It "returns null for null input" {
            $result = Resolve-UsdPath $null
            $result | Should BeNullOrEmpty
        }
        
        It "returns null for empty string" {
            $result = Resolve-UsdPath ""
            $result | Should BeNullOrEmpty
        }
        
        It "returns original path for non-existent path" {
            $fakePath = "C:\NonExistent\Path\file.usd"
            $result = Resolve-UsdPath $fakePath
            $result | Should Be $fakePath
        }
    }
    
    Context "Import-UsdOverrides" {
        $testXmlPath = Join-Path $script:fixtureDir "test_overrides.xml"
        $invalidXmlPath = Join-Path $script:fixtureDir "invalid.xml"
        $nonExistentPath = Join-Path $script:fixtureDir "nonexistent.xml"
        
        It "loads hashtable from valid XML file" {
            if (Test-Path $testXmlPath) {
                $result = Import-UsdOverrides $testXmlPath
                $result.GetType().Name | Should Be "Hashtable"
            }
        }
        
        It "returns empty hashtable for non-existent file" {
            $result = Import-UsdOverrides $nonExistentPath
            $result.GetType().Name | Should Be "Hashtable"
            $result.Keys.Count | Should Be 0
        }
        
        It "returns empty hashtable for invalid XML with warning" {
            if (Test-Path $invalidXmlPath) {
                $result = Import-UsdOverrides $invalidXmlPath
                $result.GetType().Name | Should Be "Hashtable"
                $result.Keys.Count | Should Be 0
            }
        }
    }
    
    Context "Export-UsdOverrides" {
        $tempXmlPath = Join-Path $TestDrive "temp_overrides.xml"
        
        It "saves hashtable to XML file" {
            $testData = @{
                "C:\test\file1.usd" = @{ resScale = 100; padding = 4 }
                "C:\test\file2.usd" = @{ resScale = 50; padding = 5 }
            }
            
            Export-UsdOverrides $testData $tempXmlPath
            Test-Path $tempXmlPath | Should Be $true
            
            $loaded = Import-UsdOverrides $tempXmlPath
            $loaded.Keys.Count | Should Be 2
        }
        
        It "saves empty hashtable" {
            $emptyData = @{}
            Export-UsdOverrides $emptyData $tempXmlPath
            Test-Path $tempXmlPath | Should Be $true
        }
    }
    
    Context "Import-ConfigIni" {
        $testIniPath = Join-Path $script:fixtureDir "test_config.ini"
        $nonExistentIniPath = Join-Path $script:fixtureDir "nonexistent.ini"
        
        It "loads configuration from valid INI file" {
            if (Test-Path $testIniPath) {
                $result = Import-ConfigIni $testIniPath
                $result.GetType().Name | Should Be "Hashtable"
                $result.Keys.Count | Should BeGreaterThan 0
            }
        }
        
        It "merges default configuration" {
            $defaults = @{ KEY1 = "default1"; KEY2 = "default2" }
            $result = Import-ConfigIni $nonExistentIniPath $defaults
            $result.Keys.Count | Should Be 2
            $result["KEY1"] | Should Be "default1"
        }
        
        It "INI file values override defaults" {
            if (Test-Path $testIniPath) {
                $defaults = @{ HOUDINI_BIN = "C:\Default\Path" }
                $result = Import-ConfigIni $testIniPath $defaults
                $result["HOUDINI_BIN"] | Should Not Be "C:\Default\Path"
            }
        }
        
        It "returns empty hashtable for non-existent INI file" {
            $result = Import-ConfigIni $nonExistentIniPath
            $result.GetType().Name | Should Be "Hashtable"
            $result.Keys.Count | Should Be 0
        }
    }
    
    Context "Get-USDFrameRange" {
        It "returns null when hython.exe does not exist" {
            $fakeHouBin = "C:\NonExistent\Houdini\bin"
            $fakeUsdPath = "C:\test.usd"
            $result = Get-USDFrameRange $fakeUsdPath $fakeHouBin
            $result | Should BeNullOrEmpty
        }
    }
    
    Context "Convert-RangePairs" {
        It "normalizes hashtable array" {
            $input = @(
                @{ start = 1; end = 10 },
                @{ start = 20; end = 30 }
            )
            $result = Convert-RangePairs $input
            $result.Count | Should Be 2
            $result[0].start | Should Be 1
            $result[0].end | Should Be 10
        }
        
        It "converts old-style array format" {
            $input = @(
                @(1, 10),
                @(20, 30)
            )
            $result = Convert-RangePairs $input
            $result.Count | Should Be 2
            $result[0].start | Should Be 1
            $result[0].end | Should Be 10
        }
        
        It "converts single-element array to same range" {
            $input = @(@(5))
            $result = Convert-RangePairs $input
            $result.Count | Should Be 1
            $result[0].start | Should Be 5
            $result[0].end | Should Be 5
        }
        
        It "returns empty array for null input" {
            $result = Convert-RangePairs $null
            $result.Count | Should Be 0
        }
        
        It "returns empty array for empty array input" {
            $result = Convert-RangePairs @()
            $result.Count | Should Be 0
        }
    }
    
    Context "ConvertFrom-RangeText" {
        It "parses single range" {
            $result = ConvertFrom-RangeText "1-10"
            $result.Count | Should Be 1
            $result[0].start | Should Be 1
            $result[0].end | Should Be 10
        }
        
        It "parses multiple ranges" {
            $result = ConvertFrom-RangeText "1-10,20-30,40-50"
            $result.Count | Should Be 3
            $result[1].start | Should Be 20
            $result[1].end | Should Be 30
        }
        
        It "parses single frame" {
            $result = ConvertFrom-RangeText "5"
            $result.Count | Should Be 1
            $result[0].start | Should Be 5
            $result[0].end | Should Be 5
        }
        
        It "parses mixed ranges and single frames" {
            $result = ConvertFrom-RangeText "1-10,20,30-40"
            $result.Count | Should Be 3
            $result[1].start | Should Be 20
            $result[1].end | Should Be 20
        }
        
        It "parses negative frame numbers" {
            $result = ConvertFrom-RangeText "-10--5,0,5-10"
            $result.Count | Should Be 3
            $result[0].start | Should Be -10
            $result[0].end | Should Be -5
        }
        
        It "parses input with whitespace" {
            $result = ConvertFrom-RangeText " 1 - 10 , 20 , 30 - 40 "
            $result.Count | Should Be 3
        }
        
        It "returns empty array for empty string" {
            $result = ConvertFrom-RangeText ""
            $result.Count | Should Be 0
        }
        
        It "returns empty array for null input" {
            $result = ConvertFrom-RangeText $null
            $result.Count | Should Be 0
        }
        
        It "returns null for invalid format" {
            $result = ConvertFrom-RangeText "abc"
            $result | Should BeNullOrEmpty
        }
        
        It "returns null for invalid range format" {
            $result = ConvertFrom-RangeText "1-10-20"
            $result | Should BeNullOrEmpty
        }
        
        It "returns null for partially invalid input" {
            $input = "1-10,abc,20-30"
            $result = ConvertFrom-RangeText $input
            $result | Should BeNullOrEmpty
        }
    }
}

