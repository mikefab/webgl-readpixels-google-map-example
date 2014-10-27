#= require hamlcoffee
#= require_tree ./templates
#= require_self
angular.module('myApp',  ['myApp.controllers', 'myApp.directives', 'myApp.services'])


        
angular.module('myApp.controllers', [])
  .controller 'myCtrl', ($scope) ->
    canvasLayer                = undefined
    $scope.gl                  = undefined
    $scope.pointProgram        = undefined
    $scope.pointArrayBuffer    = undefined
    $scope.colorLookup         = {}
    
    pixelsToWebGLMatrix  = new Float32Array(16)
    mapMatrix            = new Float32Array(16)
    $scope.shaderProgram = undefined
    $scope.colorLookup   = {}

    
    $scope.cities = [{'id':'Algiers', 'latitude': 36.70000, 'longitude': 3.21700} ,{'id': 'Khartoum', 'latitude': 15.56670, 'longitude': 32.60000 },{'id': 'New York', 'latitude': 40.75170, 'longitude': -73.99420},{'id': 'London', 'latitude': 51.50722, 'longitude': -0.12750}, {'id': 'Bogota', 'latitude': 4.63330, 'longitude': -74.09990}, {'id': 'Paris', 'latitude': 48.85000, 'longitude': 2.33330}]
    $scope.init = ->

      # initialize the map
      mapOptions =
        zoom: 3
        center: new google.maps.LatLng(24.026397, 14.765625)
        mapTypeId: google.maps.MapTypeId.ROADMAP
      $scope.map = new google.maps.Map(document.getElementById('map'), mapOptions)

      
    $scope.initialize_canvasLayer = ->
      canvasLayerOptions =
        map: $scope.map
        resizeHandler: resize
        animate: false
        updateHandler: $scope.update

      canvasLayer = new CanvasLayer(canvasLayerOptions)
      # initialize WebGL
      $scope.gl = canvasLayer.canvas.getContext('experimental-webgl',
        preserveDrawingBuffer: true
      )
      canvas = document.getElementById('map')
      height = 1024
      width  = 1024
      
      canvas.addEventListener 'mousemove', (ev) ->
        x    = undefined
        y    = undefined
        top  = 0
        left = 0
        obj  = canvas
        while obj and obj.tagName isnt 'BODY'
          top  += obj.offsetTop
          left += obj.offsetLeft
          obj   = obj.offsetParent
        left += window.pageXOffset
        top  -= window.pageYOffset
        x     = ev.clientX - left
        y     = canvas.clientHeight - (ev.clientY - top)
        
        pixels = new Uint8Array(4)
        $scope.gl.readPixels x, y, 1, 1, $scope.gl.RGBA, $scope.gl.UNSIGNED_BYTE, pixels

        d = document.getElementById('infoWindow')
        if $scope.colorLookup[pixels[0] + ' ' + pixels[1] + ' ' + pixels[2]]
          d.style.display = 'inline'
          d.style.left    = ev.x + 10 + 'px'
          d.style.top     = ev.y - 15 + 'px'
          d.innerHTML     = $scope.colorLookup[pixels[0] + ' ' + pixels[1] + ' ' + pixels[2]]
        else
          d.style.display = 'none'        
      
      $scope.animate()
      
    $scope.$on 'handleMapSet', ->
      $scope.init()
      $scope.initialize_canvasLayer()
      $scope.createShaderProgram()
      
    resize = ->
      width  = canvasLayer.canvas.width
      height = canvasLayer.canvas.height
      $scope.gl.viewport 0, 0, width, height
    
      # matrix which maps pixel coordinates to WebGL coordinates
      pixelsToWebGLMatrix.set [2 / width, 0, 0, 0, 0, -2 / height, 0, 0, 0, 0, 0, 0, -1, 1, 0, 1]
    
    
    $scope.update = (mapService) ->

      $scope.gl.clear $scope.gl.COLOR_BUFFER_BIT
      currentZoom = $scope.map.zoom
      mapProjection = $scope.map.getProjection()

      ###
      We need to create a transformation that takes world coordinate
      points in the pointArrayBuffer to the coodinates WebGL expects.
      1. Start with second half in pixelsToWebGLMatrix, which takes pixel
      coordinates to WebGL coordinates.
      2. Scale and translate to take world coordinates to pixel coords
      see https://developers.google.com/maps/documentation/javascript/maptypes#MapCoordinate
      ###

      # copy pixel->webgl matrix
      mapMatrix.set pixelsToWebGLMatrix

      # Scale to current zoom (worldCoords * 2^zoom)
      scale = Math.pow(2, $scope.map.zoom)
      scaleMatrix mapMatrix, scale, scale

      # translate to current view (vector from topLeft to 0,0)

      offset = mapProjection.fromLatLngToPoint(canvasLayer.getTopLeft())
      translateMatrix mapMatrix, -offset.x, -offset.y

      # attach matrix value to 'mapMatrix' uniform in shader
      matrixLoc = $scope.gl.getUniformLocation($scope.pointProgram, 'mapMatrix')
      $scope.gl.uniformMatrix4fv matrixLoc, false, mapMatrix

      # On SCREEN
      # Bind Shader attributes
      $scope.gl.bindFramebuffer($scope.gl.FRAMEBUFFER, $scope.framebuffer);
      $scope.gl.bindBuffer($scope.gl.ARRAY_BUFFER, $scope.pointArrayBuffer)           # Bind world coord
      attributeLoc = $scope.gl.getAttribLocation($scope.pointProgram, 'worldCoord')
      $scope.gl.enableVertexAttribArray attributeLoc
      $scope.gl.vertexAttribPointer attributeLoc, 2, $scope.gl.FLOAT, false, 0, 0
      
      $scope.gl.bindBuffer($scope.gl.ARRAY_BUFFER, $scope.sizeArrayBuffer)            # Bind point size
      attributeSize = $scope.gl.getAttribLocation($scope.pointProgram, 'aPointSize')
      $scope.gl.enableVertexAttribArray attributeSize
      $scope.gl.vertexAttribPointer attributeSize, 1, $scope.gl.FLOAT, false, 0, 0
      
      $scope.gl.bindBuffer($scope.gl.ARRAY_BUFFER, $scope.colorArrayBufferOffScreen)   # Bind point color
      attributeCol = $scope.gl.getAttribLocation($scope.pointProgram, 'color')
      $scope.gl.enableVertexAttribArray attributeCol     
      $scope.gl.vertexAttribPointer attributeCol, 4, $scope.gl.FLOAT, false, 0, 0
      
      # tell webgl how buffer is laid out (pairs of x,y coords)
      
      l = $scope.point_xy.length / 2

      $scope.gl.drawArrays $scope.gl.POINTS, 0, l
      $scope.gl.bindFramebuffer $scope.gl.FRAMEBUFFER, null

    
    $scope.createShaderProgram = ->
      # create vertex shader
      vertexSrc    = document.getElementById('pointVertexShader').text
      vertexShader = $scope.gl.createShader($scope.gl.VERTEX_SHADER)
      $scope.gl.shaderSource vertexShader, vertexSrc
      $scope.gl.compileShader vertexShader

      # create fragment shader
      fragmentSrc    = document.getElementById('pointFragmentShader').text
      fragmentShader = $scope.gl.createShader($scope.gl.FRAGMENT_SHADER)
      $scope.gl.shaderSource fragmentShader, fragmentSrc
      $scope.gl.compileShader fragmentShader

      # link shaders to create our program
      $scope.pointProgram = $scope.gl.createProgram()
      $scope.gl.attachShader $scope.pointProgram, vertexShader
      $scope.gl.attachShader $scope.pointProgram, fragmentShader
      $scope.gl.linkProgram $scope.pointProgram
      $scope.gl.useProgram $scope.pointProgram 
    
 
    $scope.animate = ->
      city_dots            = point_data($scope.cities)

      $scope.point_xy      = city_dots.point_xy    # Typed array of x,y pairs
      $scope.point_color   = city_dots.point_color # Typed array of sets of four floating points
      $scope.point_size    = city_dots.point_size
    
      $scope.pointArrayBuffer = $scope.gl.createBuffer()                                        # pointArrayBuffer
      $scope.gl.bindBuffer $scope.gl.ARRAY_BUFFER, $scope.pointArrayBuffer
      $scope.gl.bufferData $scope.gl.ARRAY_BUFFER, city_dots.point_xy, $scope.gl.STATIC_DRAW

      $scope.sizeArrayBuffer = $scope.gl.createBuffer()                                         # pSizeArrayBuffer
      $scope.gl.bindBuffer $scope.gl.ARRAY_BUFFER, $scope.sizeArrayBuffer
      $scope.gl.bufferData $scope.gl.ARRAY_BUFFER, city_dots.point_size, $scope.gl.STATIC_DRAW

      $scope.colorArrayBufferOffScreen = $scope.gl.createBuffer()                                 # pColorArrayBuffer
      $scope.gl.bindBuffer $scope.gl.ARRAY_BUFFER, $scope.colorArrayBufferOffScreen
      $scope.gl.bufferData $scope.gl.ARRAY_BUFFER, city_dots.point_color, $scope.gl.STATIC_DRAW

    
    point_data      =  (city_data) ->
      point_xy      = new Float32Array(2 * city_data.length)
      point_color   = new Float32Array(4 * city_data.length)
      point_size    = new Float32Array(    city_data.length)

      i = 0
      while i < city_data.length
        lat = city_data[i]['latitude']       
        lon = city_data[i]['longitude']
        id  = city_data[i]['id']
  
        pixel                = LatLongToPixelXY(lat, lon)
        point_xy[i * 2]      = pixel.x
        point_xy[i * 2 + 1]  = pixel.y
        point_size[i]        = 20.0 unless point_size[i] # Has already been spotted as a retweeted tweet
  
        fst = Math.random()
        snd = Math.random()
        trd = Math.random()
        # Generate a random color 
        $scope.colorLookup[Math.abs(Math.round(fst*255)) + ' ' +  Math.abs(Math.round(snd*255))+ ' ' +  Math.abs(Math.round(trd*255))] = id
        
        # On screen point colors
        point_color[i * 4]     =  fst
        point_color[i * 4 + 1] =  snd
        point_color[i * 4 + 2] =  trd
        point_color[i * 4 + 3] =  1
        i++
      

      {point_color: point_color,  point_xy: point_xy, point_size: point_size}    
    

angular.module('myApp.services', [])
  .factory 'mapService', ($rootScope) ->
      mapService = {}
      mapService.map = undefined
      mapService.set_map = (map) ->
        this.map = map
        $rootScope.$broadcast('handleMapSet')
      return mapService
     

angular.module('myApp.directives', [])
  .directive('appVersion', ['version', (version)->
    (scope, elm, attrs)->
      elm.text(version)
  ])
  
  .directive 'map', (mapService) ->    
    replace: true
    template: '<div></div>'
    link: (scope, element, attrs) ->
      console.log element
      mapOptions =
        zoom: 3
        center: new google.maps.LatLng(24.026397, 14.765625)
        mapTypeId: google.maps.MapTypeId.ROADMAP
      mapService.set_map new google.maps.Map(document.getElementById('map'), mapOptions)
      
  
scaleMatrix = (matrix, scaleX, scaleY) ->
  # scaling x and y, which is just scaling first two columns of matrix
  matrix[0] *= scaleX
  matrix[1] *= scaleX
  matrix[2] *= scaleX
  matrix[3] *= scaleX
  matrix[4] *= scaleY
  matrix[5] *= scaleY
  matrix[6] *= scaleY
  matrix[7] *= scaleY

translateMatrix = (matrix, tx, ty) ->
  # translation is in last column of matrix
  matrix[12] += matrix[0] * tx + matrix[4] * ty
  matrix[13] += matrix[1] * tx + matrix[5] * ty
  matrix[14] += matrix[2] * tx + matrix[6] * ty
  matrix[15] += matrix[3] * tx + matrix[7] * ty
  
  
LatLongToPixelXY = (latitude, longitude) ->
  sinLatitude = Math.sin(latitude * pi_180)
  pixelY = (0.5 - Math.log((1 + sinLatitude) / (1 - sinLatitude)) / (pi_4)) * 256
  pixelX = ((longitude + 180) / 360) * 256
  pixel =
    x: pixelX
    y: pixelY

  pixel
pi_180 = Math.PI / 180.0
pi_4 = Math.PI * 4
