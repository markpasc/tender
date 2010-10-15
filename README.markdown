## tender, a bot for running agile style standups in IRC ##

tender is an IRC bot that helps you run standups for distributed teams using IRC.

    #team:
    [11:00] <      tender> Time for standup! It's in #standup

    #standup:
    [11:00] <      tender> Time for standup! Tell me 'start' when everyone's
                           here.
    [11:00]            --> bob has joined #standup
    [11:00]            --> alice has joined #standup
    [11:00] <    markpasc> tender: start
    [11:00] <      tender> alice: your turn
    [11:00] <       alice> i did some stuff and it was pretty awesome
    [11:00] <       alice> tender: next
    [11:00] <      tender> bob: your turn
    [11:01] <         bob> i also got some things done
    [11:01] <         bob> today i'm hell of rocking something else
    [11:01] <         bob> i forgot i had to talk to alice about getting the
                           splines reticulated though
    [11:02] <       alice> tender: park reticulating the splines
    [11:02] <      tender> alice: Parked.
    [11:02] <         bob> tender: next
    [11:02] <      tender> markpasc: your turn
    [11:02] <    markpasc> i also did some awesome stuff but today's stuff is
                           even more awesomer
    [11:02] <    markpasc> tender: next
    [11:02] <      tender> All done! Standup was 2 minutes.

    back in #team:
    [11:02] <      tender> Parked topics:
    [11:02] <      tender>  * reticulating the splines


### Getting started ###

You'll need these things to run tender:

* Perl 5.10
* Bot::BasicBot::Pluggable
* Try::Tiny
* POE::Component::Schedule
* DateTime::Event::Cron

Once you have these, copy the `standup-example.yaml` to `standup.yaml` and customize it for your team. Specify any of [Bot::BasicBot's attributes][bbnew] to set them for your bot. One attribute of particular note is:

* `ignore_list`: the names of people to ignore. Include the other bots you use in your standup channel here and they won't be called on.

The standups are configured in the `standups` setting. It's a list in case you want to run multiple standups on your server, but you probably only have one at first. For each standup you can specify:

* `id`: a code name for that team.
* `team_channel`: the channel the team normally chats in. The bot announces standups to this channel, and afterward pastes the parking lot there.
* `standup_channel`: the channel to run the standup in. Anyone in this channel (except for other bots named in the `ignore_list`) are considered "the team" and will be called on during the standup. If you have no lurking chickens, this can be the same as the `team_channel`.
* `schedule`: a cron style specification for when your standups are. See `man 5 crontab` for how to write one of these. If not specified, standups only happen when started manually with the `standup` command.
* `schedule_tz`: the time zone `schedule` is specified in. This is also the main time zone used by the `when` command, so it should be the primary time zone for your team. If not specified, times are in UTC.
* `additional_tz`: another time zone your team uses. The `when` command also says what time the next standup is in this time zone. If not specified, `when` only lists one time zone.

Once you've configured it, run:

    $ perl Standup.pm

to start the bot.

[bbnew]: http://search.cpan.org/dist/Bot-BasicBot/lib/Bot/BasicBot.pm#ATTRIBUTES


### Using tender ###

Standups are better when held at a regular time, so when you can, configure tender with a schedule. Tender will tell you when it's time to have the meeting (though a little warning is always nice, so you should still keep a meeting alarm in your calendar). Use the `when` command to ask tender it will call the next scheduled standup. When you need to hold a standup at an odd time, or if you can't really schedule your team's standup, you can ask for a standup manually with the `standup` command.

After using `standup` or if a standup was scheduled, you can start the standup with `start` or cancel it with `cancel`.

Once the standup starts, the last person to arrive in the standup channel will be called on first. Once you've given your update, use the `next` command to pass to someone else. Once everyone has gone, tender will say so and end the meeting. If you wonder who hasn't yet taken their turns, you can ask with the `left` command. (Don't worry if someone arrives late: as long as they join the standup channel before the last person has gone, they'll get called on to take their turn.)

During the meeting, if a topic comes up that needs discussion, park it for later with the `park <topic>` command. Tender will repeat these topics in the team channel when the meeting is over.

Everyone should try to stay present during the meeting to help keep it short. However if someone had to go AFK and it becomes their turn, you can also use the `next` command during someone else's turn to come back to them later. Tender will pick someone else to go next instead. However, if everyone else has gone, they might be the only team member left to pick, and will get picked again immediately. If someone is in the standup channel accidentally when they aren't actually present, use the `skip <name>` command and they'll be skipped for the whole meeting. (Avoid being that person by not lurking in the standup channel between meetings.)

* `standup`: manually asks for a standup.
* `start`: begins a standup that was scheduled or asked for with `standup`.
* `cancel`: cancels a standup that was scheduled or asked for, before it's started with `start`.
* `next`: finishes your turn, passing it to someone else.
* `skip <name>`: skips over someone for the rest of the meeting.
* `park <topic>`: park a topic for later.
* `left`: asks who hasn't yet taken their turns in the open meeting.
* `when`: asks when the next scheduled standup will be.
* `help`: ask tender about these commands.
