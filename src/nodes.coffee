Context = require './context'

class Base
    prepare: -> @

    compile: ->

Document = class exports.Document extends Base
    constructor: (sections) ->
        @type = 'Document'
        @sections = sections

    prepare: -> @

    compile: (system) ->
        code = ''
        for section in @sections
            code += section.prepare(system).compile(system)
        if system.config.addMammouth
            code = mammouthFunction + code
        return code

RawText = class exports.RawText extends Base
    constructor: (text = '') ->
        @type = 'RawText'
        @text = text

    compile: ->
        return @text

Script = class exports.Script extends Base
    constructor: (block) ->
        @type = 'Script'
        @body = block

    prepare: ->
        @body.braces = off
        @

    compile: (system) ->
        code = '<?php'
        code += @body.prepare(system).compile(system);
        code += '?>'
        return code

Block = class exports.Block extends Base
    constructor: (instructions = []) ->
        @type = 'Block'
        @body = instructions
        @braces = on
        @expands = off

    activateReturn: (returnGen = Express) ->
        return if @body.length is 0
        lastIndex = @body.length - 1
        switch @body[lastIndex].type
            when 'For', 'If', 'Switch', 'Try', 'While'
                @body[lastIndex].activateReturn(returnGen)
            when 'Break', 'Declare', 'Echo', 'Goto', 'Interface', 'Namespace', 'Section', 'Throw'
                return
            when 'Return'
                if @body[lastIndex].value is off
                    @body.pop()
            else
                @body[lastIndex] = returnGen(@body[lastIndex])

    prepare: ->
        for instruction, i in @body
            instruction.isStatement = on
            switch instruction.type
                when 'Assign', 'Call', 'Clone', 'Code', 'Goto', 'Break', 'Constant', 'Continue', 'Declare', 'Delete', 'GetKeyAssign', 'Global', 'Echo', 'Include', 'Namespace', 'NewExpression', 'Operation', 'Require', 'Return', 'Throw', 'typeCasting', 'Value'
                    if instruction.type is 'Code' and instruction.body isnt off
                        break
                    if instruction.type is 'Namespace' and instruction.body isnt off
                        break
                    if instruction.type is 'Declare' and instruction.script isnt off
                        break
                    if instruction.type is 'Value' and instruction.value.type is 'Parens' and instruction.properties.length is 0
                        instruction = instruction.value.expression
                    expression = new Expression instruction
                    expression.isStatement = on
                    @body[i] = expression
        @

    compile: (system) ->
        if @braces and @body.length is 0
            return '{}'
        code = ''
        code += '{' if @braces
        if @body.length is 1 and @body[0].type is 'Expression' and not @expands
            code += ' ' + @body[0].prepare(system).compile(system) + (if @braces then' }' else ' ')
        else
            system.indent.up()
            code += '\n'
            for instruction, i in @body
                compiled = instruction.prepare(system).compile(system)
                if compiled isnt off
                    code += system.indent.get() + compiled
                    code += '\n'
            system.indent.down()
            code += system.indent.get() + '}' if @braces
        return code

Expression = class exports.Expression extends Base
    constructor: (expression) ->
        @type = 'Expression'
        @expression = expression

    compile: (system) ->
        if @expression.type is 'Value' and @expression.value.type is 'Literal' and typeof @expression.value.value is 'string'
            if @expression.value.value.replace(/[ ]+/g, ' ') is 'strict mode'
                system.setStrictMode()
                return off
            if @expression.value.value.replace(/[ ]+/g, ' ') is 'default mode'
                system.setDefaultConfig()
                return off
        return @expression.prepare(system).compile(system) + ';'

Value = class exports.Value extends Base
    constructor: (value, properties = []) ->
        @type = 'Value'
        @value = value
        @properties = properties

    add: (prop) ->
        @properties.push(prop)
        @

    compile: (system) ->
        if @value.type is 'Existence' and @properties.length > 0
            existence = new Existence @value.value
            @value = @value.value
            expression = new If existence, new Block([@])
            if @isStatement
                expression.isStatement = on
            return expression.prepare(system).compile(system)
        if @isStatement
            @value.isStatement = on
        code = @value.prepare(system).compile(system)
        for propertie in @properties
            code += propertie.prepare(system).compile(system)
        return code

Access = class exports.Access extends Base
    constructor: (value, method = ".") ->
        @type = 'Access'
        @value = value
        @method = method

    compile: (system) ->
        switch @method
            when '->', '.'
                code = "->" + @value.name
            when '::', '..'
                code = '::' + @value.name
            when '[]'
                code = '[' + @value.prepare(system).compile(system) + ']'
        return code;

Identifier = class exports.Identifier extends Base
    constructor: (name) ->
        @type = 'Identifier'
        @name = name

    compile: (system) ->
        if not system.context.has @name 
            system.context.push new Context.Name @name
        return system.context.Identify(@name)

HereDoc = class exports.HereDoc extends Base
    constructor: (heredoc) ->
        @type = 'HereDoc'
        @heredoc = heredoc

    compile: (system) ->
        return '<<<EOT\n' + @heredoc + '\nEOT'

Literal = class exports.Literal extends Base
    constructor: (raw) ->
        @type = 'Literal'
        @value = eval raw
        @raw = raw

    compile: (system) ->
        return @raw

Array = class exports.Array extends Base
    constructor: (elements = []) ->
        @type = 'Array'
        @elements = elements

    compile: (system) ->
        code = 'array('
        for element, i in @elements
                code += element.prepare(system).compile(system)
                if i isnt @elements.length - 1
                    code += ', '
        code += ')'
        return code

ArrayKey = class exports.ArrayKey extends Base
    constructor: (key, value) ->
        @type = 'ArrayKey'
        @key = key
        @value = value

    compile: (system) ->
        return @key.prepare(system).compile(system) + ' => ' + @value.prepare(system).compile(system)

Parens = class exports.Parens extends Base
    constructor: (expression) ->
        @type = 'Parens'
        @expression = expression

    compile: (system) ->
        return '(' + @expression.prepare(system).compile(system) + ')'

typeCasting = class exports.typeCasting extends Base
    constructor: (expression, ctype) ->
        @type = 'typeCasting'
        @expression = expression
        @ctype = ctype

    compile: (system) ->
        return '(' + @ctype + ') ' + @expression.prepare(system).compile(system) 

Clone = class exports.Clone extends Base
    constructor: (expression) ->
        @type = 'Clone'
        @expression = expression

    compile: (system) ->
        return 'clone ' + @expression.prepare(system).compile(system)

Call = class exports.Call extends Base
    constructor: (callee, args = []) ->
        @type = 'Call'
        @callee = callee
        @arguments = args

    prepare: ->
        for arg, i in @arguments
            if arg.type is 'Value' and arg.value.type is 'Parens'
                @arguments[i] = arg.value.expression
        @

    compile: (system) ->
        if @callee.value? and @callee.value.type is 'Existence'
            existence = new Existence @callee.value.value
            callee = new Value @callee.value.value
            for prop in @callee.value.value
                callee.add prop
            for prop in @callee.properties
                callee.add prop
            expression = new If existence, new Block([new Call callee, @arguments])
            if @isStatement
                expression.isStatement = on
            return expression.prepare(system).compile(system)
        code = @callee.prepare(system).compile(system)
        code += '('
        for arg, i in @arguments
            code += arg.prepare(system).compile(system)
            if i isnt @arguments.length - 1
                    code += ', '
        code += ')'
        return code

NewExpression = class exports.NewExpression extends Base
    constructor: (callee, args = []) ->
        @type = 'NewExpression'
        @callee = callee
        @arguments = args

    compile: (system) ->
        code = 'new ' + @callee.prepare(system).compile(system)
        code += '('
        for arg, i in @arguments
            code += arg.prepare(system).compile(system)
            if i isnt @arguments.length - 1
                    code += ', '
        code += ')'
        return code

Existence = class exports.Existence extends Base
    constructor: (value) ->
        @type = 'Existence'
        @value = value

    compile: (system) ->
        return 'isset(' + @value.prepare(system).compile(system) + ')'

Range = class exports.Range extends Base
    constructor: (from, to, tag) ->
        @type = 'Range'
        @from = from
        @to = to
        @exclusive = tag is 'exclusive'

    prepare: () ->
        if @from instanceof Value and
                @from.value instanceof Literal and
                typeof @from.value.value is 'number'
            @fromCache = @from.value.value
        if @to instanceof Value and
                @to.value instanceof Literal and
                typeof @to.value.value is 'number'
            @toCache = @to.value.value
        if typeof @fromCache is 'number' and typeof @toCache is 'number' and Math.abs(@fromCache - @toCache) <= 20
            @compileResult = 'Array'
        else
            @compileResult = 'function'
        @

    compile: (system) ->
        if @compileResult is 'Array'
            array = if @exclusive then [@fromCache...@toCache] else [@fromCache..@toCache]
            return (new Array(new Literal(i.toString()) for i in array)).prepare(system).compile()
        else
            index = new Identifier system.context.free('i')
            expression = new Call(
                new Identifier 'call_user_func'
                [new Code(
                    [], new Block([
                        new For {source: @, index: index, range: on}, new Block [new Value index]
                    ])
                )]
            )
            return expression.prepare(system).compile(system)

Slice = class exports.Slice extends Base
    constructor: (range) ->
        @type = 'Slice'
        @range = range

    compile: (system) ->
        param = []
        if @range.from?
            param.push @range.from
        else
            param.push new Value new Literal '0'
        if @range.to?
            param.push if @range.exclusive then @range.to else new Operation '+', @range.to, new Literal '1'
        param = [
            new Literal '"slice"'
            @value
        ].concat param
        system.config.addMammouth = on
        expression = new Call(
            new Identifier 'mammouth'
            param
        )
        return expression.prepare(system).compile(system)

QualifiedName = class exports.QualifiedName extends Base
    constructor: (path) ->
        @type = 'QualifiedName'
        @path = path

    compile: (system) ->
        return @path

# Operations
Assign = class exports.Assign extends Base
    constructor: (operator, left, right) ->
        @type = 'Assign'
        @operator = operator
        @left = left
        @right = right

    compile: (system) ->
        if @left.type is 'Value' and @left.value.type is 'Identifier'
            system.context.push new Context.Name @left.value.name
        code = @left.prepare(system).compile(system)
        code += ' ' + @operator + ' ' 
        code += @right.prepare(system).compile(system)
        return code

GetKeyAssign = class exports.GetKeyAssign extends Base
    constructor: (keys, source) ->
        @type = 'GetKeyAssign'
        @keys = keys
        @source = source

    compile: (system) ->
        code = ''
        for key, i in @keys
            if i isnt 0
                code += system.indent.get()
            left = (new Value key)
            @source.properties = []
            @source.add(new Access (new Value new Literal '"' + key.name + '"'), '[]')
            code += (new Assign '=', left, @source).prepare(system).compile(system)
            if i isnt @keys.length - 1
                code += ';\n'
        return code

Constant = class exports.Constant extends Base
    constructor: (left, right) ->
        @type = 'Constant'
        @left = left
        @right = right

    compile: (system) ->
        system.context.push new Context.Name @left, 'const'
        return 'const ' + @left + ' = ' + @right.prepare(system).compile(system)

Unary = class exports.Unary extends Base
    constructor: (operator, expression) ->
        @type = 'Unary'
        @operator = operator
        @expression = expression

    compile: (system) ->
        return @operator + @expression.prepare(system).compile(system)

Update = class exports.Update extends Base
    constructor: (operator, expression, prefix = on) ->
        @type = 'Update'
        @operator = operator
        @expression = expression
        @prefix = prefix

    compile: (system) ->
        code = @expression.prepare(system).compile(system)
        if @prefix then code = @operator + code else code += @operator
        return code

Operation = class exports.Operation extends Base
    constructor: (operator, left, right) ->
        @type = 'Operation'
        @operator = operator
        @left = left
        @right = right

    compile: (system) ->
        if @operator is 'in'
            return (new Value(new Call(
                new Value(new Identifier 'in_array')
                [
                   @left
                   @right 
                ]
            ))).prepare(system).compile(system)
        code = @left.prepare(system).compile(system)
        if @operator is '~'
            @operator = '.'
        space = if @operator isnt '.' then ' ' else ''
        if @operator is '+' and system.config['+'] is on
            system.config.addMammouth = on
            expression = new Value new Call(
                new Value new Identifier 'mammouth'
                [
                    new Value new Literal '"+"'
                    @left
                    @right
                ]
            )
            return expression.prepare(system).compile(system)
        code += space + @operator + space
        code += @right.prepare(system).compile(system)
        return code

Code = class exports.Code extends Base
    constructor: (parameters, body = off, asStatement = off, name = null) ->
        @type = 'Code'
        @parameters = parameters
        @body = body
        @asStatement = asStatement
        @name = name
        @uses = false

    setUses: (list) ->
        @uses = list
        @

    prepare: ->
        if @body isnt off
            @body.activateReturn((exp) -> new Return exp)
        @

    compile: (system) ->
        code = "function" + (if @asStatement then ' ' + @name else '') + '('
        system.context.push new Context.Name @name, 'function'
        system.context.scopeStarts()
        for parameter, i in @parameters
            code += parameter.prepare(system).compile(system)
            if i isnt @parameters.length - 1
                code += ', '
        code += ')'
        # Check for use
        if @uses isnt false
            code += ' use ('
            for parameter, i in @uses
                code += parameter.prepare(system).compile(system)
                if i isnt @uses.length - 1
                    code += ', '
            code += ')'
        if @body isnt false
            code += ' ' + @body.prepare(system).compile(system)
        system.context.scopeEnds()
        return code;
        
Param = class exports.Param extends Base
    constructor: (name, passing = off, hasDefault = off, def = null) ->
        @type = 'Param'
        @name = name
        @passing = passing
        @hasDefault = hasDefault
        @default = def

    compile: (system) ->
        system.context.push new Context.Name @name
        code = (if @passing then '&' else '')
        code += '$' + @name
        code += (if @hasDefault then ' = ' + @default.prepare(system).compile(system) else '')
        return code

# If
If = class exports.If extends Base
    constructor: (condition, body, invert = off) ->
        @type = 'If'
        @condition = if invert then new Unary("!", new Parens condition) else condition
        @body = body
        @elses = []
        @closed = off

    addElse: (element) ->
        @elses.push(element)
        return @

    activateReturn: (returnGen) ->
        @body.activateReturn(returnGen)
        for els in @elses
            els.activateReturn(returnGen)

    prepare: () ->
        @body.expands = on 
        for els in @elses
            els.parentIf = @
            if @isStatement
                els.isStatement = on
            els.body.expands = on
        if not @isStatement
            if @body.body.length is 1
                @body = @body.body[0]
        @

    compile: (system) ->
        if @isStatement
            code = 'if(' + @condition.prepare(system).compile(system) + ') '
            code += @body.prepare(system).compile(system)
            for els in @elses
                code += els.prepare(system).compile(system)
        else
            code = @condition.prepare(system).compile(system) + ' ? ' + @body.prepare(system).compile(system)
            for els in @elses
                code += ' : ' + els.prepare(system).compile(system)
            if not @closed
                code += ' : NULL';
        return code
        

ElseIf = class exports.ElseIf extends Base
    constructor: (condition, body) ->
        @type = 'ElseIf'
        @condition = condition
        @body = body

    activateReturn: (returnGen) ->
        @body.activateReturn(returnGen)

    prepare: ->
        if not @isStatement
            if @body.body.length is 1
                @body = @body.body[0]
        @

    compile: (system) ->
        if @isStatement
            code = ' elseif(' + @condition.prepare(system).compile(system) + ') '
            code += @body.prepare(system).compile(system)
        else
            code = @condition.prepare(system).compile(system) + ' ? ' + @body.prepare(system).compile(system)
        return code

Else = class exports.Else extends Base
    constructor: (body) ->
        @type = 'Else'
        @body = body

    activateReturn: (returnGen) ->
        @body.activateReturn(returnGen)

    prepare: ->
        if not @isStatement
            if @body.body.length is 1
                @body = @body.body[0]
        @

    compile: (system) ->
        if @isStatement
            code = ' else '
            code += @body.prepare(system).compile(system)
        else
            @parentIf.closed = on
            code = @body.prepare(system).compile(system)
        return code

# While
While = class exports.While extends Base
    constructor: (test, invert = off, guard = null, block = null) ->
        @type = 'While'
        @test = if invert then new Unary("!", test) else test
        @guard = guard
        @body = block
        @returnactived = off
        if block isnt null
            delete @guard

    addBody: (block) ->
        @body = if @guard isnt null then new Block([new If(@guard, block)]) else block
        delete @guard
        return @

    activateReturn: (returnGen) ->
        @returnactived = on

    prepare: (system) ->
        @body.expands = on
        if @returnactived
            @cacheRes = cacheRes = new Identifier system.context.free('result')
            funcgen = (exp) ->
                m = new Expression(new Call(
                    new Value(new Identifier('array_push')),
                    [new Value(cacheRes), exp]
                ))
                return m
            @body.activateReturn(funcgen);
        @

    compile: (system) ->
        code = ''
        if @isStatement
            if @returnactived
                init = new Expression new Assign '=', new Value(@cacheRes), new Value(new Array())
                code += init.prepare(system).compile(system)
                code += '\n' + system.indent.get()
            code += 'while(' + @test.prepare(system).compile(system) + ') '
            code += @body.prepare(system).compile(system)
            if @returnactived
                code += '\n' + system.indent.get()
                code += (new Expression new Return new Value @cacheRes).prepare(system).compile(system)
        else
            @isStatement = on
            code += (new Value(
                new Call(
                    new Identifier 'call_user_func'
                    [new Code(
                        []
                        new Block [@]
                    )]
                )
            )).prepare(system).compile(system)
        return code

# Try
Try = class exports.Try extends Base
    constructor: (TryBody, CatchBody = new Block, CatchIdentifier = off, FinallyBody = off) ->
        @type = 'Try'
        @TryBody = TryBody
        @CatchBody = CatchBody
        @CatchIdentifier = CatchIdentifier
        @FinallyBody = FinallyBody

    activateReturn: (returnGen) ->
        @TryBody.activateReturn(returnGen)
        @CatchBody.activateReturn(returnGen)
        if @FinallyBody isnt off
            @FinallyBody.activateReturn(returnGen)

    prepare: (system) ->
        @TryBody.expands = on
        @CatchBody.expands = on
        if @FinallyBody isnt off
            @FinallyBody.expands = on
        @

    compile: (system) ->
        code = ''
        if @isStatement
            code += 'try '
            code += @TryBody.prepare(system).compile(system)
            code += ' catch(Exception '
            if @CatchIdentifier is off
                code += (new Identifier system.context.free('error')).prepare(system).compile(system)
            else
                code += @CatchIdentifier.prepare(system).compile(system)
            code += ') ' + @CatchBody.prepare(system).compile(system)
        else
            @isStatement = on
            code += (new Value(
                new Call(
                    new Identifier 'call_user_func'
                    [new Code(
                        []
                        new Block [@]
                    )]
                )
            )).prepare(system).compile(system)
        return code

# For
For = class exports.For extends Base
    constructor: (source, block) ->
        @type = 'For'
        @source = source
        @body = block
        @returnactived = off
        @isPrepared = off

    activateReturn: (returnGen) ->
        @returnactived = on

    prepare: (system) ->
        @body.expands = on
        @object = !!@source.object
        if not(@source.range? and @source.range is on) and not @isPrepared
            if not @object
                @cacheIndex = new Identifier system.context.free('i')
                @cacheLen = new Identifier system.context.free('len')
                if @source.source.type is 'Value' and @source.source.value.type is 'Identifier'
                    @initRef = off
                    @cacheRef = @source.source.value
                else
                    @initRef = on
                    @cacheRef = new Identifier system.context.free('ref')
                valfromRef = new Value(@cacheRef)
                valfromRef.add(new Access((if @source.index? then @source.index else @cacheIndex), '[]'))
                addTop = on
        if @source.guard? and not @isPrepared
            @body = new Block([new If(@source.guard, @body)])
        if addTop is on and not @isPrepared
            @body.body.unshift new Expression new Assign(
                '='
                @source.name
                valfromRef
            )
        if @returnactived
                @cacheRes = cacheRes = new Identifier system.context.free('result')
                funcgen = (exp) ->
                    m = new Expression(new Call(
                        new Value(new Identifier('array_push')),
                        [new Value(cacheRes), exp]
                    ))
                    return m
                @body.activateReturn(funcgen);
        @

    compile: (system) ->
        code = ''
        if @isStatement
            if @returnactived
                init = new Expression new Assign '=', new Value(@cacheRes), new Value(new Array())
                code += init.prepare(system).compile(system)
                code += '\n' + system.indent.get()
            if @source.range? and @source.range is on
                index = if @source.index? then @source.index else new Identifier system.context.free('i')
                code += 'for(' 
                code += (new Assign(
                    '='
                    index
                    @source.source.from
                )).prepare(system).compile(system)
                code += '; '
                code += (new Operation(
                    if @source.source.exclusive then '<' else '<='
                    index
                    @source.source.to
                )).prepare(system).compile(system)
                code += '; '
                if @source.step?
                    update = new Assign '+=', index, @source.step
                else
                    update = new Update '++', index, off
                code += (update).prepare(system).compile(system)
                code += ') '
                code += @body.prepare(system).compile(system)
            else
                if @object
                    code += 'foreach(' + @source.source.prepare(system).compile(system) + ' as '
                    code += @source.name.prepare(system).compile(system)
                    code += ' => '
                    if @source.index?
                        code += @source.index.prepare(system).compile(system)
                    else
                        code += (new Identifier system.context.free('value')).prepare(system).compile(system)
                    code += ') '
                    code += @body.prepare(system).compile(system)
                else
                    index = @cacheIndex
                    len = @cacheLen
                    if @initRef
                        init = new Expression new Assign '=', new Value(@cacheRef), @source.source
                        code += init.prepare(system).compile(system)
                        code += '\n' + system.indent.get()
                    code += 'for(' 
                    if @source.index?
                        code += (new Assign(
                            '='
                            @source.index
                            new Value(new Assign('=', index, new Value(new Literal('0'))))
                        )).prepare(system).compile(system)
                    else
                        code += (new Assign(
                            '='
                            index
                            new Value new Literal '0'
                        )).prepare(system).compile(system)
                    code += ', '
                    system.config.addMammouth = on
                    code += (new Assign(
                        '='
                        len
                        new Value new Call(
                            new Identifier('mammouth')
                            [
                                new Value new Literal("'length'")
                                @cacheRef
                            ]
                        )
                    )).prepare(system).compile(system)
                    code += '; '
                    code += (new Operation(
                        '<'
                        index
                        len
                    )).prepare(system).compile(system)
                    code += '; '
                    if @source.step?
                        update = new Assign '+=', index, @source.step
                    else
                        update = new Update '++', index, off
                    if @source.index?
                        code += (new Assign(
                            '='
                            @source.index
                            new Value(update)
                        )).prepare(system).compile(system)
                    else
                        code += (update).prepare(system).compile(system)
                    code += ') '
                    code += @body.prepare(system).compile(system)
            if @returnactived
                code += '\n' + system.indent.get()
                code += (new Expression new Return new Value @cacheRes).prepare(system).compile(system)
        else
            @isStatement = on
            @isPrepared = on
            code += (new Value(
                new Call(
                    new Identifier 'call_user_func'
                    [new Code(
                        []
                        new Block [@]
                    )]
                )
            )).prepare(system).compile(system)
        return code


# For
Switch = class exports.Switch extends Base
    constructor: (subject = null, whens, otherwise = off) ->
        @type = 'Switch'
        @subject = if subject is null then new Value(new Literal 'false') else subject
        @whens = whens
        if subject is null
            for whe in @whens
                for val, i in whe[0]
                    whe[0][i] = new Value new Unary '!', new Parens val
        @otherwise = otherwise
        @isPrepared = off
        @returnactived = off

    activateReturn: (returnGen) ->
        @returnactived = true
        for whe in @whens
            whe[1].activateReturn(returnGen)
        if @otherwise isnt off
            @otherwise.activateReturn(returnGen)

    compile: (system) ->
        code =''
        if @isStatement
            for whe in @whens
                whe[1].expands = on
                whe[1].braces = off
                lastndex = whe[1].body.length - 1
                if not (whe[1].body[lastndex].type in ['Return', 'Break']) and not @returnactived
                    whe[1].body.push new Break
            if @otherwise isnt off
                @otherwise.expands = on
                @otherwise.braces = off
            code += 'switch(' + @subject.prepare(system).compile(system) + ') {\n'
            system.indent.up()
            for whe in @whens
                for val, i in whe[0]
                    if i isnt 0
                        code += '\n'
                    code += system.indent.get() + 'case ' + val.prepare(system).compile(system) + ':'
                code += whe[1].prepare(system).compile(system)
            if @otherwise isnt off
                code += system.indent.get() + 'default:'
                code += @otherwise.prepare(system).compile(system)
            system.indent.down()
            code += system.indent.get() + '}'
        else
            @isStatement = on
            @isPrepared = on
            @activateReturn((exp) -> new Return exp)
            code += (new Value(
                new Call(
                    new Identifier 'call_user_func'
                    [new Code(
                        []
                        new Block [@]
                    )]
                )
            )).prepare(system).compile(system)
        return code

# Declare
Declare = class exports.Declare extends Base
    constructor: (expression, script = off) ->
        @type = 'Declare'
        @expression = expression
        @script = script

    prepare: (system) ->
        if @script isnt off
            @script.expands = on
        @

    compile: (system) ->
        if @expression.type is 'Assign' and @expression.left.type is 'Value' and @expression.left.value.type is 'Identifier'
            system.context.push new Context.Name @expression.left.value.name, 'const'
        code = 'declare(' + @expression.prepare(system).compile(system) + ')'
        if @script isnt off
            code += ' ' + @script.prepare(system).compile(system)
        return code

# Section
Section = class exports.Section extends Base
    constructor: (name) ->
        @type = 'Section'
        @name = name

    compile: (system) ->
        return @name + ':'

# Jump Statement
Goto = class exports.Goto extends Base
    constructor: (section) ->
        @type = 'Goto'
        @section = section

    compile: (system) ->
        return 'goto ' + @section

Break = class exports.Break extends Base
    constructor: (arg = off) ->
        @type = 'Break'
        @arg = arg

    compile: (system) ->
        return 'break' + (if @arg is off then '' else ' ' + @arg.prepare(system).compile(system))

Continue = class exports.Continue extends Base
    constructor: (arg = off) ->
        @type = 'Continue'
        @arg = arg

    compile: (system) ->
        return 'continue' + (if @arg is off then '' else ' ' + @arg.prepare(system).compile(system))

Return = class exports.Return extends Base
    constructor: (value = off) ->
        @type = 'Return'
        @value = value

    compile: (system) ->
        return 'return' + (if @value is off then '' else ' ' + @value.prepare(system).compile(system))

Throw = class exports.Throw extends Base
    constructor: (expression) ->
        @type = 'Throw'
        @expression = expression

    compile: (system) ->
        return 'throw ' + @expression.prepare(system).compile(system)

Echo = class exports.Echo extends Base
    constructor: (value) ->
        @type = 'Echo'
        @value = value

    compile: (system) ->
        return 'echo ' + @value.prepare(system).compile(system)

Delete = class exports.Delete extends Base
    constructor: (value) ->
        @type = 'Delete'
        @value = value

    compile: (system) ->
        return 'delete ' + @value.prepare(system).compile(system)

Global = class exports.Global extends Base
    constructor: (vars) ->
        @type = 'Delete'
        @vars = vars

    compile: (system) ->
        res = 'global '
        for vari, i in @vars
            res += vari.prepare(system).compile(system)
            if i isnt @vars.length - 1
                res += ', '
        return res

# Class
Class = class exports.Class extends Base
    constructor: (name, body, extendable = off, implement = off, modifier = off) ->
        @type = "Class"
        @name = name
        @body = body
        @extendable = extendable
        @implement = implement
        @modifier = modifier

    prepare: (system) ->
        for line, i in @body
            if line.element.type is 'Code' and line.element.body is false
                @body[i].element = new Expression line.element
        @

    compile: (system) ->
        system.context.push new Context.Name @name, 'class'
        code = (if @modifier isnt off then @modifier + ' ' else '') + 'class ' + @name
        if @extendable isnt false
            code += ' extends ' + @extendable.prepare(system).compile(system)
        if @implement isnt false
            code += ' implements '
            for impl, i in @implement
                code += impl.prepare(system).compile(system)
                if i isnt @implement.length - 1
                    code += ', '
        code += '\n' + system.indent.get() + '{\n'
        system.indent.up()
        for line, i in @body
            code += system.indent.get() + line.prepare(system).compile(system)
            code += '\n'
        system.indent.down()
        code += system.indent.get() + '}'
        return code

ClassLine = class exports.ClassLine extends Base
    constructor: (visibility, statically, element) ->
        @type = 'ClassLine'
        @abstract = off
        @finaly = off
        @visibility = visibility
        @statically = statically
        @element = element

    compile: (system) ->
        code = ''
        if @abstract is on
            code += 'abstract '
        if @finaly is on
            code += 'final '
        if @visibility isnt off
            code += @visibility + ' '
        if @statically isnt off
            code += @statically + ' '
        code += @element.prepare(system).compile(system)
        return code

# Interface
Interface = class exports.Interface extends Base
    constructor: (name, body, extendable = off) ->
        @type = "Interface"
        @name = name
        @body = body
        @extendable = extendable

    prepare: (system) ->
        for line, i in @body
            if line.element.type is 'Code' and line.element.body is false
                @body[i].element = new Expression line.element
        @

    compile: (system) ->
        system.context.push new Context.Name @name, 'interface'
        code = 'interface ' + @name
        if @extendable isnt false
            code += ' extends ' + @extendable.prepare(system).compile(system)
        code += '\n' + system.indent.get() + '{\n'
        system.indent.up()
        for line, i in @body
            code += system.indent.get() + line.prepare(system).compile(system)
            code += '\n'
        system.indent.down()
        code += system.indent.get() + '}'
        return code

# Namespace
Namespace = class exports.Namespace extends Base
    constructor: (name, body = off) ->
        @type = 'Namespace'
        @name = name
        @body = body

    prepare: (system) ->
        if @body isnt off
            @body.expands = on
        @

    compile: (system) ->
        code = 'namespace ' + @name.prepare(system).compile(system)
        if @body isnt off
            system.context.scopeStarts()
            code += ' ' + @body.prepare(system).compile(system)
            system.context.scopeEnds()
        return code

# Importing
Include = class exports.Include extends Base
    constructor: (path, once = off) ->
        @type = 'Include'
        @path = path
        @once = once

    compile: (system) ->
        code = ''
        if @once
            code += 'include_once '
        else
            code += 'include '
        if @path.type is 'Value' and @path.value.type is 'Literal'
            literal = @path.value.value
            if typeof literal is 'string' and system.config['import']
                path = literal
                system.Mammouth.contextify(path)
                if literal[-9...] is '.mammouth'
                    @path.value.raw = @path.value.raw[...-10] + '.php' + @path.value.raw[-1...]
                if literal[-4...] is '.mmt'
                    @path.value.raw = @path.value.raw[...-5] + '.php' + @path.value.raw[-1...]
        code += @path.prepare(system).compile(system)
        return code

Require = class exports.Require extends Base
    constructor: (path, once = off) ->
        @type = 'Require'
        @path = path
        @once = once

    compile: (system) ->
        code = ''
        if @once
            code += 'require_once '
        else
            code += 'require '
        if @path.type is 'Value' and @path.value.type is 'Literal'
            literal = @path.value.value
            if typeof literal is 'string' and system.config['import']
                path = literal
                system.Mammouth.contextify(path)
                if literal[-9...] is '.mammouth'
                    @path.value.raw = @path.value.raw[...-10] + '.php' + @path.value.raw[-1...]
                if literal[-4...] is '.mmt'
                    @path.value.raw = @path.value.raw[...-5] + '.php' + @path.value.raw[-1...]
        code += @path.prepare(system).compile(system)
        return code

mammouthFunction = "<?php
  function mammouth() {
    $arguments = func_get_args();
    switch($arguments[0]) {
      case '+':
        if((is_string($arguments[1]) && is_numeric($arguments[2])) || (is_string($arguments[1]) && is_numeric($arguments[1]))) {
          return $arguments[1].$arguments[2];
        } else {
          return $arguments[1] + $arguments[2];
        }
        break;
      case 'length':
        if(is_array($arguments[1])) {
          return count($arguments[1]);
        } elseif(is_string($arguments[1])) {
          return strlen($arguments[1]);
        } elseif(is_numeric($arguments[1])) {
          return strlen((string) $arguments[1]);
        }
        break;
      case 'slice':
        if(is_array($arguments[1])) {
          if(count($arguments) === 3) {
            return array_slice($arguments[1], $arguments[2]);
          } else {
            return array_slice($arguments[1], $arguments[2], $arguments[3] - $arguments[2]);
          }
        } elseif(is_string($arguments[1])) {
          if(count($arguments) === 3) {
            return substr($arguments[1], $arguments[2]);
          } else {
            return substr($arguments[1], $arguments[2], $arguments[3] - $arguments[2]);
          }
        } elseif(is_numeric($arguments[1])) {
          if(count($arguments) === 3) {
            return mammouth('slice', (string) $arguments[1], $arguments[2]);
          } else {
            return mammouth('slice', (string) $arguments[1], $arguments[2], $arguments[3] - $arguments[2]);
          }
        }
        break;
    }
  }
?>\n"