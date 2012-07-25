class @Chart extends Backbone.Model
  defaults:
    'container': 'main_chart'

  initialize : ->
    # every chart has a series (=~ gqueries) collection. This helps us handling
    # them
    @series = switch @get('type')
      when 'block' then new BlockChartSeries()
      when 'scatter' then new ScatterChartSeries()
      else new ChartSeries()
    @bind('change:type', @render)
    @render()

  render : =>
    return false unless @supported_by_current_browser()
    type = @get('type')
    d3_support = Browser.hasD3Support() && !window.disable_d3
    view_class = switch type
      when 'bezier'
        if d3_support
          D3.bezier.View
        else
          BezierChartView
      when 'horizontal_stacked_bar' then HorizontalStackedBarChartView
      when 'mekko'
        if d3_support
          D3.mekko.View
        else
          MekkoChartView
      when 'waterfall'              then WaterfallChartView
      when 'vertical_stacked_bar'
        if d3_support
          D3.stacked_bar.View
        else
          VerticalStackedBarChartView
      when 'grouped_vertical_bar'   then GroupedVerticalBarChartView
      when 'policy_bar'             then PolicyBarChartView
      when 'line'                   then LineChartView
      when 'block'                  then BlockChartView
      when 'vertical_bar'           then VerticalBarChartView
      when 'html_table'             then HtmlTableChartView
      when 'scatter'                then ScatterChartView
      when 'd3'                     then @d3_view_factory()
      when 'sankey'                 then D3.sankey.View
      else HtmlTableChartView
    @view = new view_class
      model: this
      el: @outer_container()
    @view.update_title()
    @view

  # the container just holds the chart, the outer container has the chart
  # action links, title, etc.
  outer_container: => $('#' + @get('container')).parents(".chart_holder")

  # D3 charts have their own class. Let's make an instance of the right one
  # D3 is a pseudo-namespace. See d3_chart_view.coffee
  d3_view_factory: =>
    key = @.get 'key'
    if D3[key] && D3[key].View
      D3[key].View
    else
      throw "No such D3 chart: #{ key }"

  # @return [ApiResultArray] = [
  #   [[2010,0.4],[2040,0.6]],
  #   [[2010,20.4],2040,210.4]]
  # ]
  results : (exclude_target) ->
    if exclude_target
      series = @non_target_series()
    else
      series = @series.toArray()

    out = _(series).map (serie) -> serie.result()

    # policy goal charts show percentages but the gqueries return values
    # in the [0,1] range. Let's take care of that
    if @get('percentage')
      out = _(out).map (serie) ->
        [
          [ serie[0][0], serie[0][1] * 100 ],
          [ serie[1][0], serie[1][1] * 100 ]
        ]
    out

  colors : ->
    @series.map (serie) -> serie.get('color')

  labels : ->
    @series.map (serie) -> serie.get('label')

  # @return [Float] Only values of the present
  values_present: ->
    exclude_target_series = true
    _.map @results(exclude_target_series), (result) ->  result[0][1]

  # @return [Float] Only values of the future
  values_future : ->
    exclude_target_series = true
    _.map @results(exclude_target_series), (result) -> result[1][1]

  # @return [Float] All possible values. Helpful to determine min/max values
  values : ->
    _.flatten([@values_present(), @values_future()])

  # @return [[Float,Float]] Array of present/future values [Float,Float]
  value_pairs :->
    @series.map (serie) -> serie.result_pairs()

  non_target_series : ->
    @series.reject (serie) -> serie.get('is_target_line')

  target_series : ->
    @series.select (serie) -> serie.get('is_target_line')

  # @return Array of present and future target
  target_results : ->
    _.flatten _.map(@target_series(), (serie) -> serie.future_value())

  # @return Array of hashes {label, present_value, future_value}
  series_hash : ->
    @series.map (serie) ->
      label : serie.get('label')
      present_value : serie.present_value()
      future_value : serie.future_value()

  # This is used to show a chart as a table
  # See base_chart_view#render_as_table
  formatted_series_hash : ->
    # the @non_target_series() array is wrapped in underscore to fix an IE8 bug
    items = _(@non_target_series()).map (serie) =>
      label = serie.get 'label'
      label = "#{label} - #{serie.get('group')}" if @get('type') == 'mekko'
      out =
        label: label
        present_value: Metric.autoscale_value(serie.present_value(), @get('unit'), 2)
        future_value: Metric.autoscale_value(serie.future_value(), @get('unit'), 2)
    # some charts draw series bottom to top. Let's flip the array
    return items.reverse() if @get('type') in ['vertical_stacked_bar', 'bezier']
    items

  # raw array of the associated gqueries. Delegates to the collection object
  #
  gqueries: => @series.gqueries()

  # let's get rid of the gqueries we don't need anymore. This is called when we
  # remove a chart and don't want stale gqueries lying around.
  #
  delete_gqueries: =>
    g.release() for g in @gqueries()
    gqueries.cleanup()

  supported_by_current_browser: =>
    if @get('type') == 'd3' && !Browser.hasD3Support()
      false
    else
      true

  delete: =>
    @view.unbind()
    @delete_gqueries()

  shown_as_table: => @view.display_as_table

  can_be_shown_as_table: => @view.can_be_shown_as_table()

class @ChartList extends Backbone.Collection
  model : Chart

  initialize: ->
    $.jqplot.config.enablePlugins = true
    @setup_callbacks()

  # table and cost charts are HTML-based. Their HTML is returned by the Rails app
  # and the Backbone app takes care of inserting it into the DOM adding
  # the gqueries result values. This hash stores the HTML for the charts
  # using the chart_id as key.
  html: {}

  # We can have multiple charts. This hash keeps track ok which chart holders
  # are being used
  chart_holders: {}

  # Loads a chart. Parameters:
  # - holder_id: id of the dom element that will hold the chart
  # - options: hash with these keys:
  #  - wait: if true an api_call won't be fired immediately. Useful when we want
  #    to show multiple charts on the same page
  #  - alternate: id of the chart to load if the first one fails. Watch out for
  #    loops!
  #
  # TODO: refactor, too much stuff is happening here!
  #
  load : (chart_id, holder_id = 'main_chart', options = {}) =>
    if @pinned_chart_in(holder_id) || @current_chart_in(holder_id) == chart_id
      return false

    wait = options.wait || false
    alternate = options.alternate || false

    App.debug('Loading chart: #' + chart_id)
    App.debug "#{window.location.origin}/admin/output_elements/#{chart_id}"
    url = "/output_elements/#{chart_id}"
    $.ajax
      url: url
      success: (data) =>
        # store the chart HTML (tables and block chart)
        @html[chart_id] = data.html
        # Add to the Chart constructor options the id of the container element
        data.attributes.container = holder_id
        # Remember what we were showing in that position
        old_chart = @chart_holders[holder_id]
        # Create the new Chart
        new_chart = new Chart(data.attributes)
        if !new_chart.supported_by_current_browser()
          if alternate
            @load alternate, holder_id
          else
            alert I18n.t('output_elements.common.old_browser')
          return false

        # Remember where the chart is
        @chart_holders[holder_id] = new_chart
        old_chart.delete() if old_chart
        # Deal with the collection object
        @remove old_chart
        @add new_chart
        # Pass the gqueries to the chart
        for s in data.series
          s.owner = holder_id
          new_chart.series.add(s)

        # if the chart was pinned as table let's set the instance variable
        show_as_table = try
          App.settings.get('charts')[holder_id].format == 'table'
        catch e
          null

        if show_as_table
          new_chart.view.display_as_table = true

        # Now it's time to upate the buttons and links for the chart
        root = $('#' + holder_id).parents('.chart_holder')

        # show/hide default chart button - only for the chart holders that
        # actually define a default chart. The dashboard popups charts don't.
        if container_info = App.settings.get('charts')[holder_id]
          default_chart_for_holder = container_info.default
          root.find("a.default_chart").toggle(chart_id != default_chart_for_holder)

        # show/hide format toggle button
        root.find("a.chart_format, a.table_format").hide()
        if show_as_table && new_chart.can_be_shown_as_table()
          root.find("a.chart_format").show()
        if new_chart.can_be_shown_as_table() && !show_as_table
          root.find("a.table_format").show()

        # update chart information link
        root.find(".actions a.chart_info").attr(
          "href", "/descriptions/charts/#{chart_id}")
        # show.hide the under_construction notice
        root.find(".chart_not_finished").toggle new_chart.get("under_construction")
        App.call_api() unless wait
    @last()

  # returns the current chart id
  current_id : => @current().get('id') if @current()

  # returns the main chart
  current: -> @chart_holders['main_chart']

  # ugly
  remove_pin: (holder_id) =>
    chart_settings = App.settings.get('charts')
    chart_settings[holder_id].chart_id = false
    chart_settings[holder_id].format = null
    App.settings.save({charts: chart_settings})
    holder = $('#' + holder_id).parents('.chart_holder')
    holder.find("a.pin_chart").removeClass("icon-lock").addClass("icon-unlock")

  # returns the id of the chart pinned in a holder - or null
  pinned_chart_in: (holder_id) =>
    try
      App.settings.get('charts')[holder_id].chart_id
    catch e
      null

  # returns the id of the chart currently shown in a holder
  current_chart_in: (holder_id) =>
    try
      @chart_holders[holder_id].get 'id'
    catch e
      null

  # The default is defined for the main chart only
  load_default: =>
    @remove_pin 'main_chart'
    @load(App.settings.get('charts').main_chart.default, 'main_chart')

  # TODO: Most of this stuff should be moved to a backbone view. Unfortunately
  # there are some issues with the event bindings leaving zombies around:
  # http://lostechies.com/derickbailey/2011/09/15/zombies-run-managing-page-transitions-in-backbone-apps/
  setup_callbacks: ->
    # chart selection pop-up. Drops pinned chart for that holder and resets the
    # chart format
    $(document).on "click", "a.pick_charts", (e) =>
      holder_id = $(e.target).parents('a').data('chart_holder')
      chart_id = $(e.target).parents('a').data('chart_id')

      chart_settings = App.settings.get('charts')
      chart_settings[holder_id].chart_id = null
      chart_settings[holder_id].format = null
      App.settings.save({charts: chart_settings})

      @load chart_id, holder_id
      close_fancybox()

    $(document).on 'click', "a.pin_chart", (e) =>
      e.preventDefault()
      # which chart are we talking about?
      holder_id = $(e.target).parents(".chart_holder").data('holder_id')
      chart = @chart_holders[holder_id]
      chart_id = chart.get('id')
      format = if chart.shown_as_table() then 'table' else 'chart'

      chart_settings = App.settings.get('charts')
      if @pinned_chart_in(holder_id)
        # the pin is being removed
        value = false
        format = null
      else
        value = chart_id

      chart_settings[holder_id].chart_id = value
      chart_settings[holder_id].format = format
      App.settings.save({charts: chart_settings})

      $(e.target).toggleClass("icon-lock", !!value)
      $(e.target).toggleClass("icon-unlock", !!!value)

    # link to open the secondary chart
    # The busybox setup will open the chart selection popup (see fancybox.coffee)
    $(document).on 'click', 'a.add_secondary_chart', (e) =>
      e.preventDefault()
      # Just show the chart holder
      $(".chart_holder.hidden").removeClass('.hidden').show()
      $(e.target).remove()

    $(document).on 'click', 'a.table_format, a.chart_format', (e) =>
      e.preventDefault()
      holder_id = $(e.target).parents(".chart_holder").data('holder_id')
      @chart_holders[holder_id].view.toggle_format()

window.charts = new ChartList()
