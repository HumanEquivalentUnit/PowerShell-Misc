# A node in the Trie represents one character of a name,
# and keeps track of whether it was the end of a name,
# so that we can distinguish 'Sam' from 'Samantha'.
class TrieNode
{
   # Char represented by this node
   [char] $char

   # if this node marks the end of a name,
   # keep some details on the name.
   [hashtable] $nameDetails

   # links to child nodes
   [System.Collections.SortedList] $childNodes
   
   [uint32] $depth

   # Constructor
   TrieNode ([char] $char, [uint32] $depth)
   {
       $this.char = [char]::ToLowerInvariant($char)
       $this.depth = $depth
       $this.childNodes = [System.Collections.Generic.SortedList[[char], [TrieNode]]]::new()
   }

   [TrieNode] FindChildNode ([char] $c)
   {
        $c = [char]::ToLowerInvariant($c)
        $result = if ($this.childNodes.Contains($c)) { $this.childNodes[$c] } else { $null }
        return $result
   }
}

# Trie main class implements adding and finding strings
class Trie
{
    [TrieNode] $root

    # Walk down the trie for this name's characters
    # and return the deepest matching node.
    # It is the shared prefix between the new name and the trie
    [TrieNode] Prefix([string] $name)
    {
        $currentNode = $this.root
        $result = $currentNode
        foreach ($char in $name.GetEnumerator()) {
            $currentNode = $currentNode.FindChildNode($char)
            if (-not $currentNode) { break }
            $result = $currentNode
        }
        
        return $result
    }

    # Searches for a name and returns details or null
    [hashtable] Search([string] $name)
    {
        $lastFoundNode = $this.Prefix($name)
        $result = if ($lastFoundNode.depth -eq $name.Length -and $null -ne $lastFoundNode.nameDetails)
        {
            $lastFoundNode.nameDetails
        }
        else
        {
            $null
        }
        return $result
    }

    # Try to insert a name, 
    # or update an existing one so we can add 'Sam' as more than one gender
    [void] Insert([string] $name, [string]$gender='', [decimal]$frequency=0.0)
    {
        $name = $name.Trim().ToLowerInvariant()
        $commonPrefix = $this.Prefix($name)
        $current = $commonPrefix

        # updating existing name
        if ($name.Length -le $commonPrefix.depth)
        {
            if ($null -eq $commonPrefix.nameDetails) {
                $commonPrefix.nameDetails = @{}
            }
            $commonPrefix.nameDetails[$gender] = $frequency
        }
        else
        {
            foreach ($i in $current.depth..($name.Length-1)) {
                $newNode = [TrieNode]::new($name[$i], $current.depth + 1)
                $current.childNodes.Add($name[$i], $newNode)
                $current = $newNode
            }
            $current.nameDetails = @{$gender = $frequency}
        }
    }



    # Constructor, with placeholder root node
    Trie ()
    {
        $this.root = [TrieNode]::new('^', 0)
    }
}

$nameTrie = [Trie]::new()


$boysTotalCount = 6719367
$girlsTotalCount = 6549591

$total = $boysTotalCount + $girlsTotalCount

foreach ($row in Import-Csv .\namesb.txt) {
    $nameTrie.Insert($row.Name, 'm', ($row.count/$total))
}

foreach ($row in Import-Csv .\namesf.txt) {
    $nameTrie.Insert($row.Name, 'f', ($row.count/$total))    
}