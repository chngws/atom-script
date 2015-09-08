CodeContext = require './code-context'
CodeContextBuilder = require './code-context-builder'
grammarMap = require './grammars'
HeaderView = require './header-view'
ScriptOptionsView = require './script-options-view'

{View, $$} = require 'atom-space-pen-views'

AnsiFilter = require 'ansi-to-html'
stripAnsi = require 'strip-ansi'
_ = require 'underscore'

# Runs a portion of a script through an interpreter and displays it line by line
module.exports =
class ScriptView extends View
  @results: ""

  @content: ->
    @div =>
      @subview 'headerView', new HeaderView()

      # Display layout and outlets
      css = 'tool-panel panel panel-bottom padding script-view
        native-key-bindings'
      @div class: css, outlet: 'script', tabindex: -1, =>
        @div class: 'panel-body padded output', outlet: 'output'

  initialize: (
    serializeState,
    @runOptions,
    @runner
  ) ->
    @ansiFilter = new AnsiFilter
    @codeContextBuilder = new CodeContextBuilder(this)

  serialize: ->

  updateOptions: (event) -> @runOptions = event.runOptions

  setHeaderAndShowExecutionTime: (returnCode, executionTime) =>
    @display 'stdout', '[Finished in '+executionTime.toString()+'s]'
    if returnCode is 0
      @setHeaderStatus 'stop'
    else
      @setHeaderStatus 'err'

  buildCodeContext: (argType='Selection Based') ->
    @codeContextBuilder.buildCodeContext(atom.workspace.getActiveTextEditor(), argType)

  start: (argType, input = null) ->
    @resetView()
    codeContext = @buildCodeContext(argType)

    if not codeContext.lang?
      # In the future we could handle a runner without the language being part
      # of the grammar map, using the options runner
      return

    commandContext = @setupRuntime codeContext

    @runner.run(commandContext.command, commandContext.args, codeContext, input) if commandContext

  resetView: (title = 'Loading...') ->
    # Display window and load message

    # First run, create view
    atom.workspace.addBottomPanel(item: this) unless @hasParent()

    # Close any existing process and start a new one
    @stop()

    @headerView.title.text title
    @headerView.setStatus 'start'

    # Get script view ready
    @output.empty()

    # Remove the old script results
    @results = ""

  close: ->
    @stop()
    if @hasParent()
      grandParent = @script.parent().parent()
      @detach()
      grandParent.remove()

  stop: ->
    @display 'stdout', '^C'
    @headerView.setStatus 'kill'

  setupRuntime: (codeContext) ->

    # Store information about the run
    commandContext = {}

    try
      if not @runOptions.cmd? or @runOptions.cmd is ''
        # Precondition: lang? and lang of grammarMap
        commandContext.command = codeContext.shebangCommand() or grammarMap[codeContext.lang][codeContext.argType].command
      else
        commandContext.command = @runOptions.cmd

      buildArgsArray = grammarMap[codeContext.lang][codeContext.argType].args

    catch error
      err = @createGitHubIssueLink codeContext
      @handleError err

      return false

    # Update header to show the lang and file name
    if codeContext.argType is 'Line Number Based'
      @headerView.title.text "#{codeContext.lang} - #{codeContext.fileColonLine(false)}"
    else
      @headerView.title.text "#{codeContext.lang} - #{codeContext.filename}"

    try
      commandContext.args = buildArgsArray codeContext
    catch errorSendByArgs
      @handleError errorSendByArgs
      return false

    # Return setup information
    return commandContext

  createGitHubIssueLink: (codeContext) ->
    title = "Add #{codeContext.argType} support for #{codeContext.lang}"
    body = """
           ##### Platform: `#{process.platform}`
           ---
           """
    encodedURI = encodeURI("https://github.com/rgbkrk/atom-script/issues/new?title=#{title}&body=#{body}")
    # NOTE: Replace "#" after regular encoding so we don't double escape it.
    encodedURI = encodedURI.replace(/#/g, '%23')

    $$ ->
      @p class: 'block', "#{codeContext.argType} runner not available for #{codeContext.lang}."
      @p class: 'block', =>
        @text 'If it should exist, add an '
        @a href: encodedURI, 'issue on GitHub'
        @text ', or send your own pull request.'

  showUnableToRunError: (command) ->
    @output.append $$ ->
      @h1 'Unable to run'
      @pre _.escape command
      @h2 'Is it in your PATH?'
      @pre "PATH: #{_.escape process.env.PATH}"

  showNoLanguageSpecified: ->
    err = $$ ->
      @p 'You must select a language in the lower right, or save the file
        with an appropriate extension.'
    @handleError(err)

  showLanguageNotSupported: (lang) ->
    err = $$ ->
      @p class: 'block', "Command not configured for #{lang}!"
      @p class: 'block', =>
        @text 'Add an '
        @a href: "https://github.com/rgbkrk/atom-script/issues/\
          new?title=Add%20support%20for%20#{lang}", 'issue on GitHub'
        @text ' or send your own Pull Request.'
    @handleError(err)

  handleError: (err) ->
    # Display error and kill process
    @headerView.title.text 'Error'
    @headerView.setStatus 'err'
    @output.append err
    @stop()

  setHeaderStatus: (status) ->
    @headerView.setStatus status

  display: (css, line) ->
    @results += line

    if atom.config.get('script.escapeConsoleOutput')
      line = _.escape(line)

    line = @ansiFilter.toHtml(line)

    padding = parseInt(@output.css('padding-bottom'))
    scrolledToEnd =
      @script.scrollBottom() == (padding + @output.trueHeight())

    lessThanFull = @output.trueHeight() <= @script.trueHeight()

    @output.append $$ ->
      @pre class: "line #{css}", =>
        @raw line

    if atom.config.get('script.scrollWithOutput')
      if lessThanFull or scrolledToEnd
        # Scroll down in a polling loop 'cause
        # we don't know when the reflow will finish.
        # See: http://stackoverflow.com/q/5017923/407845
        do @checkScrollAgain 5

  scrollTimeout: null
  checkScrollAgain: (times) ->
    =>
      @script.scrollToBottom()

      clearTimeout @scrollTimeout
      if times > 1
        @scrollTimeout = setTimeout @checkScrollAgain(times - 1), 50

  copyResults: ->
    if @results
      atom.clipboard.write stripAnsi(@results)
