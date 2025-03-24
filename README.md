# Catalog Redirect: Generate hathifile history and compute record redirects

## NOTE: this repository has been merged with https://github.com/hathitrust/hathifiles and is no longer under independent development.

We want to generate redirects for catalog records that have been completely
replaced by.

## Developer Setup

```
git clone <URL/protocol of choice>
cd hathifile_history
docker compose build
docker compose run --rm test bin/setup
docker compose run --rm test
docker compose run --rm test bundle exec standardrb
```

## Basic usage: add_monthly_and_dump_redirects.rb

```shell
bundle exec ruby bin/add_monthly_and_dump_redirect.rb \
../archive/hathi_full_20211101.txt.gz
```

In general, the only script we really need is
`add_monthly_and_dump_redirects.rb`. It does the following:

* Find the most recent full hathfiles dump in `/.../archive/hathi_full_YYYYMMDD.txt.gz`
* Figure out current/previous month (and thus filenames) from the found
  filename
* Load up the data from `history_file/#{yyyymm_prev}.ndj.gz`
* Add the data from the passed file
* Dump the updated data to `history_file/#{yyyymm_current}.ndj.gz`
* Compute the redirects (all of them, not just new ones) and dump them
  to `redirects/redirects_#{yyyymm_current}.txt` as two-column,
  tab-delimited lines of the form `old_dead_record    current_record`

`add_monthly_and_dump_redirects.rb` can optionally take all those things as arguments;
run with `-h` to see them.


## Other scripts

`bin/dump_redirects_from_history_file history_files/202111.ndj.gz
my_redir_file.txt.gz` dumps the redirects from an existing file.

`bin/initial_load.rb` is the script that was used to load all the
monthlies to get everything up to date. It will only be useful if
we need to rebuild everything.

## Performance

Running under ruby 3.x it takes about 30-40mn.

## Idempotence-ish

Because each history file is kept, it's easy to roll back to
a given point and start from there. There's no database so no
need to roll back any data or anything complex like that.

## Using the underlying `HathifileHistory` code

```ruby

$LOAD_PATH.unshift 'lib'
require 'hathifile_history'

hh = HathifileHistory.new_from_ndj('history_files/202110.ndj.gz')
hh.add_monthly("hathi_full_20211101.txt")
hh.dump_to_ndj('history_files/202111.ndj.gz')

# Eliminate any ids that are no longer used
hh.remove_missing_htids!

# ...or just get a list of them without deleting
# missing_ids = recs.missing_htids

# Compute and dump valid record redirect pairs

File.open('redirects/redirect_202111.txt', 'w:utf-8') do |out|
  hh.redirects.each_pair do |source, sink|
    out.puts "#{source}\t#{sink}"
  end
end

```



## Generated files

**redirects_YYYYMM.txt** are tab-delimited files, two columns, each a
zero-padded record id, `old_dead_record    current_record`

**YYYYMM.ndj.txt** are json dumps of the ginormous data structure that
holds all the history data (along with some extra fields to allow easy
re-creation of the actual ruby classes upon load).

## Data explanation and memory use

This whole project is just is simple(-ish) code to build up a history of

* which HTIDs were added to which record IDs
* and when was it added
* and when was it last seen on this record in a hathifile
* and when was the record last seen in a hathifile

When a file is loaded, it computes the year/month (YYYYMM) from the filename
and notes which HTIDs are on which records, and which ids are seen at all. We
end up with a big hash keyed on record id that contain data similar to
this structure:

```ruby
{
  rec_id: "000001046",
  most_recently_seen: 202111, # record appeared in Nov 2021 hathifile
  entries: {
    "mdp.39015070574192" => {
      appeared: 200808,
      last_seen_here: 202111 # was seen on this record Nov 2021
    }
  }
}
```

Because the queries we want to do can be pretty expensive in SQL-land,
and because we have gobs of memory, the whole thing is
stored in memory for processing, and later dumped to newline-delimited JSON
(`.ndj.gz`) files for loading up again the next month.


## How redirects are computed

We reduce the computation of redirects to say that `record-A` should
redirect to `record-B` iff every record that has ever been on `record-A`
is currently on `record-B`.

Things we do _not_ redirect:
  * records whose component HTIDs have ended up on more than one record
  * records that current exist cannot be a source
  * records that no longer exist cannot be a target

To find the redirects:

* Eliminate HTIDs that don't exist anymore. Otherwise,
  `htid -> new_rec -> htid-dies` could make it seem like htids got
  split over multiple records.
* Build a hash of `htid -> current_record` by buzzing through all the
  htids and checking `most_recent_appearance`
* For each record that was not seen in the most recent load (so, deleted
  records):
  *


* Get a list of all the HTIDs that have ever moved
* For each moved HTID
  * Figure out where it currently lives (`record_current`)
  * For every _other_ record it's ever lived on `record_past`, see if
    `record_current.htids.superset?(record_past.htids)`
  * If so, set up a redirect from `record_past` to `record_current`
