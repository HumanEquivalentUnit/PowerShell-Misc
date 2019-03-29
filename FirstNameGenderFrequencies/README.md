Code to find how commonly a name is used for different genders[1].

## Usage

- Download the CSV and PS1 files

Then use it to load the names into a lookup tree (you might have to edit the .ps1, scroll to the bottom, point it to the right CSV path):

```
# load the data
PS C:\> $namesTrie = .\names.ps1

# Look for Alice, see that it's a female name.
# Value is count of how often the name appeared in the combined m+f data, 
# divided into the total count of names.
# i.e. ~0.1% of people were named Alice

PS C:\> $namesTrie.Search('alice')

Name                           Value
----                           -----
f                              0.0010510467857853



# Look for Sam, see that it's both male and female name.
# and apparently more commonly given to girls than boys.

PS C:\> $namesTrie.Search('sam')

Name                           Value
----                           -----
f                              0.00275544697895066
m                              0.000511320057949607


# i.e. someone named Alice is female, 
# someone named Sam is 5x more likely to be female



# Look for names starting with "Samue" and see they are
# male and female, but more likely male overall

PS C:\> $nameTrie.GetNamesStartingWith('samue')
samuel               (m:0.00269863363917848)
samuela              (f:0.000852200096582678, m:0.0000852200096582678)
samuele              (m:0.00298270033803937)
samueljames          (m:0.000596540067607874)
samuell              (m:0.000170440019316536)
samuella             (f:0.000880606766468767)

# NB. that names starting with "Alice" will not find "Alice"
# only "Alice___"
```


## Details

Data comes from the UK Government Office of National Statistics' dataset
["Baby names, 1996 to 2017, England and Wales"](
https://www.ons.gov.uk/peoplepopulationandcommunity/birthsdeathsandmarriages/livebirths/adhocs/009010babynames1996to2017englandandwales)
(which only records "boy" or "girl".


Code creates a Trie structure and returns it;
this is a fun tree structure which squishes down repetitive
beginnings to save space and enable cool searches, that is:

```
# very similar names:
AARON
AAROON
AARRON

# are stored as:
           /->O->N
       /->O->N
A->A->R
       \-R->O->N

# All names in one tree, loads of duplication removed!
```

It is an implementation of a Trie ported [from this code](https://visualstudiomagazine.com/articles/2015/10/20/text-pattern-search-trie-class-net.aspx), with some changes and some removals.


[1] it's descriptive of records in a dataset, not prescriptive of gender on humans.
If you use this to describe Alice and Alice objects, on your head be it.
