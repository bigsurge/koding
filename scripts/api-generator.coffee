#!/usr/bin/env coffee

require 'coffee-cache'

fs = require 'fs'
bongo = require '../servers/lib/server/bongo'

swagger =
  swagger: '2.0'
  info:
    title: 'Koding API'
    version: '0.0.2'
    description: 'Koding API for integrating your application with Koding services'
    license:
      name: 'Apache 2.0'
      url: 'http://www.apache.org/licenses/LICENSE-2.0.html'
  tags: [
    {
      name: 'system'
      description: 'System endpoints for various purposes'
    }
  ]

  schemes: [
    'http'
    'https'
  ]

  definitions:
    defaultSelector:
      type: 'object'
      properties:
        _id:
          type: 'string'
          description: 'Mongo Object ID'
          example: '582c21d43bf248161538450b'
    defaultResponse:
      type: 'object'
      properties:
        ok:
          type: 'boolean'
          description: 'If the request processed by endpoint'
          example: true
        error:
          type: 'object'
          description: 'Error description'
          example:
            message: "Something went wrong"
            name: "SomethingWentWrong"
        data:
          type: 'object'
          description: 'Result of the operation'
          example: "Hello World"
    unauthorizedRequest:
      type: 'object'
      properties:
        status:
          type: 'integer'
          description: 'HTTP Error Code'
          example: 401
        message:
          type: 'string'
          description: 'Error description'
          example: "The request is unauthorized, an api token is required."
        code:
          type: 'string'
          description: 'Error Code'
          example: "UnauthorizedRequest"

  parameters:
    instanceParam:
      in: 'path'
      name: 'id'
      description: 'Mongo ID of target instance'
      required: true
      type: 'string'
    bodyParam:
      in: 'body'
      name: 'body'
      schema: $ref: '#/definitions/defaultSelector'
      required: true
      description: 'body of the request'

  paths:
    '/-/version':
      get:
        tags: [ 'system' ]
        responses:
          '200':
            description: 'OK'


parseType = (type) ->

  type = type.toLowerCase()
  type = 'string'  if type is 'objectid'
  type = 'string'  if type is 'date'
  type = 'object'  if type is 'meta'

  return type


getProps = (prop, def, field) ->

  try
    prop.format = 'date'  if prop.type is 'Date'
    prop.type = parseType prop.type
    prop.items.type = parseType prop.items.type  if prop.items?.type
  catch e
    console.log 'Failed on field:', field
    throw e

  if prop.required
    def.required ?= []
    def.required.push field
    delete prop.required

  return prop


generateDefinition = (model) ->

  schema = model.describeSchema()
  def    = { type: 'object' }
  props  = {}

  for field, prop of schema

    if 'type' not in Object.keys prop
      props[field] = { properties: {} }
      for subfield, subprop of prop
        props[field].properties[subfield] = getProps subprop, def, field
    else
      props[field] = getProps prop, def, field

  def.properties = props

  return def


generateMethodPaths = (model, definitions, paths) ->

  name = model.name
  methods = model.getSharedMethods()

  schema = if definitions[name]
  then { $ref: "#/definitions/#{name}" }
  else { $ref: "#/definitions/defaultResponse" }

  for method, signatures of methods.statik

    if hasParams = signatures.length > 1 or signatures[0].split(',').length > 1
      parameters = [{ $ref: '#/parameters/bodyParam' }]
    else
      parameters = null

    paths["/remote.api/#{name}.#{method}"] =
      post:
        tags: [ name ]
        consumes: [ 'application/json' ]
        parameters: parameters
        responses:
          '200':
            description: 'Request processed succesfully'
            schema: $ref: "#/definitions/defaultResponse"
          '401':
            description: 'Unauthorized request'
            schema: $ref: '#/definitions/unauthorizedRequest'


  for method, signatures of methods.instance

    paths["/remote.api/#{name}.#{method}/{id}"] =
      post:
        tags: [ name ]
        consumes: [ 'application/json' ]
        parameters: [
          { $ref: '#/parameters/instanceParam' }
        ]
        responses:
          '200':
            description: 'OK'
            schema: schema


bongo.on 'apiReady', ->

  paths       = swagger.paths
  definitions = swagger.definitions

  for name, model of bongo.models

    try
      if model.schema? and model.describeSchema?
        definitions[name] = generateDefinition model
    catch e
      console.log 'Failed while building definitions:', name, e
      console.log 'Schema was:', bongo.models[name].describeSchema()
      process.exit()

    try
      generateMethodPaths model, definitions, paths
    catch e
      console.log 'Failed while building methods:', name, e
      console.log 'Methods were:', bongo.models[name].getSharedMethods()
      process.exit()

  swagger.paths = paths
  swagger.definitions = definitions

  fs.writeFileSync 'website/swagger.json', JSON.stringify swagger, ' ', 2

  process.exit()
