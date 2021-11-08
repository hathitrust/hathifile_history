# Hathifile History -- what was where when?

## Usage

```ruby

$LOAD_PATH.unshift 'lib'
require 'hathifile_history'

hh = HathifileHistory.new_from_ndj('history_files/202110.ndj.gz')
hh.add_monthly("hathi_full_20211101.txt")
hh.dump_to_ndj('history_files/202111.ndj.gz')

# Eliminate any ids that are no longer used
hh.remove_missing_htids!

# ...or just get a list of them

missing_ids = hh.missing_htids

# Compute and dump valid record redirect pairs

File.open('redirects/redirect_202111.txt', 'w:utf-8') do |out|
  hh.redirects.each_pair do |source, sink|
    out.puts "#{source}\t#{sink}"
  end
end

```

## Using the scripts

In general, the only script we really need is 
`add_monthly_and_dump_redirects.rb`. It does the following:

* Take a filename of the form `hathi_full_YYYYMMDD.txt.gz`
* Derive from the filename the current month (`yyyymm_current`) and the 
  previous_month (`yyyymm_prev`)
* Load up the data from `history_file/#{yyyymm_prev}.ndj.gz`
* Add the data from the passed file
* Dump the updated data to `history_file/#{yyyymm_current}.ndj.gz`
* Compute the redirects (all of them, not just the changes) and dump them 
  to `redirects/redirects_#{yyyymm_current}.txt` as two-column, 
  tab-delimited data.

## Generated files

**redirects_YYYYMM.txt** are tab-delimited files, two columns, each a 
record number (not zero-padded). Redirect the first to the second.

**YYYYMM.ndj.txt** are json dumps of the ginormous data structure that 
holds all the history data (along with some extra fields to allow easy 
re-creation of the actual ruby classes upon load).

## Data explanation and memory use

This whole project is just is simple(-ish) code to build up a history of 
which HTIDs were added to which record IDs, and when.

When a file is loaded, it computes the year/month (YYYYMM) from the filename
and notes which HTIDs are on which records, and which ids are seen at all. We
end up with what is essentially a pair of hashes that contain data similar to
these simple hash representations:

```ruby
# When did this HTID appear on each record, and in what file was it last seen?
htids['mdp.111111'] = {
  id:                     "mdp.39015062488807",
  most_recent_appearance: 202111,
  appearances:            [
                            { id: 5115930, dt: 200808 },
                            { id: 4480646, dt: 202109 }
                          ]
}

# Which HTIDs have ever been on this record, and on which date did
# they first appear?
recids[102843605] = {
  most_recent_appearance: 202111,
  appearances:            [
                            { id: "mdp.39015019949125", dt: 202111 },
                            { id: "mdp.39015019949125", dt: 202101 }
                          ]
}

```

Because the queries we want to do can be pretty expensive in SQL-land,
and because we have gobs of memory, the whole ginormous structure is 
stored in memory for processing, and later dumped to newline-delimited JSON
(`.ndj.gz`) files for loading up again the next month. 

In general, you can use jruby and run it with something like

```shell
bundle exec jruby -J-Xmx48G add_monthly_and_dump_redirects.rb 
```

## How redirects are computed

We reduce the computation of redirects to say that `record-A` should 
redirect to `record-B` iff every record that has ever been on `record-A` 
is currently on `record-B`.

To find these:

* Eliminate HTIDs that don't exist anymore to simplify the calculations
* Get a list of all the HTIDs that have ever moved
* For each moved HTID
  * Figure out where it currently lives (`record_current`)
  * For every _other_ record it's ever lived on `record_past`, see if 
    `record_current.htids.superset?(record_past.htids)`
  * If so, set up a redirect from `record_past` to `record_current`


