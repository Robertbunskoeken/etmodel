# Pseudo-namespace for D3 charts
@D3 = {}

# This is mostly an abstract class
# 
# The derived classes should implement the draw() method for the initial
# rendering and the refresh() for the later updates.
# They should also call @initialize_defaults() in their initialize method
class @D3ChartView extends BaseChartView
  width: 430

  height: 502

  render: =>
    unless @already_on_screen()
      @clear_container()
      @container_node().html(@html)
      @draw()
    @refresh()

  already_on_screen: =>
    @container_node().find("#d3_container").length == 1

  html: "<div id='d3_container'></div>"

  can_be_shown_as_table: -> false
