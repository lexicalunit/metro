{ConfigObserver} = require 'atom'

class EventWatchView extends HTMLElement

  # Create initial view state and element.
  initialize: (@statusBar, subscriptions) ->
    @view = @createElement('a', 'event-watch', 'inline-block')
    @data = {}
    @refreshIntervalMiliseconds = 0
    @warnThresholdMiliseconds = 0
    @displayFormat = ''

    # TODO: Move this somewhere else?
    subscriptions.add atom.commands.add 'atom-workspace', 'event-watch:update': => @update()

  # Destroys and removes this view.
  destroy: ->
    @clickSubscription?.dispose()
    @remove()

  # Attach view element to status bar and do initial setup.
  attach: ->
    @statusBar?.addLeftTile(item: this, priority: 200) # far right side
    @setup()

  # Do all initial setup for view and configuration.
  setup: ->
    @setupView()

    @data = atom.config.get('event-watch.data')

    refreshIntervalMinutes = @getConfig('event-watch.refreshIntervalMinutes', 5)
    @refreshIntervalMiliseconds = refreshIntervalMinutes * 60000

    warnThresholdMinutes = @getConfig('event-watch.warnThresholdMinutes', 3 * refreshIntervalMinutes)
    @warnThresholdMiliseconds = warnThresholdMinutes * 60000

    @displayFormat = @getConfig('event-watch.displayFormat', '$title: $time')

    @update() # immediate initial update
    setInterval((=> @update()), @refreshIntervalMiliseconds)

  # Do initial setup for this view.
  setupView: ->
    @view.href = '#'

    clickHandler = ->
      @update()
      return false

    @addEventListener('click', clickHandler)
    @clickSubscription = dispose: => @removeEventListener('click', clickHandler)

    @classList.add('inline-block') # necessiary to make this view visible
    @appendChild(@view)

  # Tries to parse a time string and return a Date object and days string.
  parseTime: (timeStr, day) ->
    dt = day
    if !dt
      dt = new Date()

    time = timeStr.match(/([0123456]{1,7})?\s*(\d+)(?::(\d\d))?\s*(am|pm)?/i)
    if !time
      return NaN

    weekDay = time[1]
    hour = parseInt(time[2], 10)
    minute = parseInt(time[3], 10) || 0
    ampm = time[4]
    am = (!ampm || ampm.toLowerCase() == 'am')
    pm = (!!ampm && ampm.toLowerCase() == 'pm')

    if hour == 12 && am
        hour = 0
    else
      hour += (hour < 12 && pm) ? 12 : 0

    dt.setHours(hour)
    dt.setMinutes(minute)
    dt.setSeconds(0, 0)
    return [dt, weekDay]

  # Returns time string formatted as HH:MM[p].
  formatTime: (date) ->
    hour = date.getHours()
    minute = date.getMinutes()
    pm = ''
    if hour >= 12
      pm = 'p'
      hour = hour - 12
    if minute < 10
      minute = "0#{minute}"
    return "#{hour}:#{minute}#{pm}"

  # Create DOM element of given type with given classes.
  createElement: (type, classes...) ->
    element = document.createElement(type)
    element.classList.add(classes...)
    return element

  # Return true if day is in the given days string or days is falsey.
  occursOn: (day, days) ->
    if !days
      return true

    dt = day
    if !dt
      dt = new Date()

    return days.indexOf(dt.getDay()) != -1

  # Return next closest time from times to the current time, NaN otherwise.
  nextClosestTime: (currentDate, times) ->
    today = new Date()
    for time in times
      [dt, days] = @parseTime(time)
      if dt > currentDate && @occursOn(today, days)
        return dt

    # fallback to earliest time tomorrow
    tomorrow = new Date()
    tomorrow.setDate(tomorrow.getDate() + 1)
    if times.length
      [dt, days] = @parseTime(times[0], tomorrow)
      if @occursOn(days, tomorrow)
        return dt

    return NaN

  # Grab given key from Atom config, or set it to fallback if not there.
  getConfig: (key, fallback) ->
    value = atom.config.get(key)
    if !value
      value = fallback
      atom.config.set(key, value)
    return value

  # Refresh view with current event information.
  update: ->
    currentDate = new Date
    events = []

    for title, times of @data
      # ignore missing titles and those starting with -
      if !title.length or title[0] == '-'
        continue

      # find next closest recurring event time
      next = @nextClosestTime(currentDate, times)
      if !next
        continue

      # apply display format
      text = @displayFormat.slice(0)
        .replace(/\$time/g, @formatTime(next))
        .replace(/\$title/g, title)

      # create event view element
      eventClasses = ['inline-block']
      if next - currentDate <= @warnThresholdMiliseconds
        eventClasses.push('warn')
      event = @createElement('span', eventClasses...)
      event.textContent = text

      events.push(event)

    # remove existing view elements first
    while @view.firstChild
      @view.removeChild(@view.firstChild)

    for event in events
      @view.appendChild(event)

module.exports = document.registerElement('event-watch',
                                          prototype: EventWatchView.prototype,
                                          extends: 'div')
