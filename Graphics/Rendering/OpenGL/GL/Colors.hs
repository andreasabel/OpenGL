--------------------------------------------------------------------------------
-- |
-- Module      :  Graphics.Rendering.OpenGL.GL.Colors
-- Copyright   :  (c) Sven Panne 2002-2009
-- License     :  BSD-style (see the file libraries/OpenGL/LICENSE)
-- 
-- Maintainer  :  sven.panne@aedion.de
-- Stability   :  stable
-- Portability :  portable
--
-- This module corresponds to section 2.14 (Colors and Coloring) of the
-- OpenGL 2.1 specs.
--
--------------------------------------------------------------------------------

module Graphics.Rendering.OpenGL.GL.Colors (
   -- * Lighting
   lighting, Light(..), light, maxLights,
   FrontFaceDirection(..), frontFace,

   -- * Lighting Parameter Specification
   Face(..),
   materialAmbient, materialDiffuse, materialAmbientAndDiffuse,
   materialSpecular, materialEmission, materialShininess, maxShininess,
   materialColorIndexes,

   ambient, diffuse, specular,
   position, spotDirection, spotExponent, maxSpotExponent, spotCutoff,
   attenuation,

   lightModelAmbient, lightModelLocalViewer, lightModelTwoSide,
   vertexProgramTwoSide,
   LightModelColorControl(..), lightModelColorControl,

   -- * ColorMaterial
   ColorMaterialParameter(..), colorMaterial,

   -- * Flatshading
   ShadingModel(..), shadeModel
) where

import Control.Monad
import Data.StateVar
import Data.Tensor
import Foreign.Marshal.Alloc
import Foreign.Marshal.Array
import Foreign.Marshal.Utils
import Foreign.Ptr
import Foreign.Storable
import Graphics.Rendering.OpenGL.GL.Capability
import Graphics.Rendering.OpenGL.GL.Face
import Graphics.Rendering.OpenGL.GL.PeekPoke
import Graphics.Rendering.OpenGL.GL.QueryUtils
import Graphics.Rendering.OpenGL.GL.VertexSpec
import Graphics.Rendering.OpenGL.GLU.ErrorsInternal
import Graphics.Rendering.OpenGL.Raw.ARB.Compatibility
import Graphics.Rendering.OpenGL.Raw.Core31

--------------------------------------------------------------------------------

lighting :: StateVar Capability
lighting = makeCapability CapLighting

--------------------------------------------------------------------------------

newtype Light = Light GLsizei
   deriving ( Eq, Ord, Show )

marshalLight :: Light -> Maybe GLenum
marshalLight (Light l) = lightIndexToEnum l

--------------------------------------------------------------------------------

light :: Light -> StateVar Capability
light (Light l) = makeCapability (CapLight l)

maxLights :: GettableStateVar GLsizei
maxLights = makeGettableStateVar (getSizei1 id GetMaxLights)

--------------------------------------------------------------------------------

data FrontFaceDirection =
     CW
   | CCW
   deriving ( Eq, Ord, Show )

marshalFrontFaceDirection :: FrontFaceDirection -> GLenum
marshalFrontFaceDirection x = case x of
   CW -> 0x900
   CCW -> 0x901

unmarshalFrontFaceDirection :: GLenum -> FrontFaceDirection
unmarshalFrontFaceDirection x
   | x == 0x900 = CW
   | x == 0x901 = CCW
   | otherwise = error ("unmarshalFrontFaceDirection: illegal value " ++ show x)

--------------------------------------------------------------------------------

frontFace :: StateVar FrontFaceDirection
frontFace =
   makeStateVar
      (getEnum1 unmarshalFrontFaceDirection GetFrontFace)
      (glFrontFace . marshalFrontFaceDirection)

--------------------------------------------------------------------------------

data MaterialParameter =
     MaterialEmission
   | MaterialShininess
   | MaterialAmbientAndDiffuse
   | MaterialColorIndexes
   | MaterialAmbient
   | MaterialDiffuse
   | MaterialSpecular

marshalMaterialParameter :: MaterialParameter -> GLenum
marshalMaterialParameter x = case x of
   MaterialEmission -> 0x1600
   MaterialShininess -> 0x1601
   MaterialAmbientAndDiffuse -> 0x1602
   MaterialColorIndexes -> 0x1603
   MaterialAmbient -> 0x1200
   MaterialDiffuse -> 0x1201
   MaterialSpecular -> 0x1202

--------------------------------------------------------------------------------

materialAmbient :: Face -> StateVar (Color4 GLfloat)
materialAmbient =
   makeMaterialVar glGetMaterialfvc glMaterialfvc MaterialAmbient

materialDiffuse :: Face -> StateVar (Color4 GLfloat)
materialDiffuse =
   makeMaterialVar glGetMaterialfvc glMaterialfvc MaterialDiffuse

materialAmbientAndDiffuse :: Face -> StateVar (Color4 GLfloat)
materialAmbientAndDiffuse =
   makeMaterialVar glGetMaterialfvc glMaterialfvc MaterialAmbientAndDiffuse

materialSpecular :: Face -> StateVar (Color4 GLfloat)
materialSpecular =
   makeMaterialVar glGetMaterialfvc glMaterialfvc MaterialSpecular

materialEmission :: Face -> StateVar (Color4 GLfloat)
materialEmission =
   makeMaterialVar glGetMaterialfvc glMaterialfvc MaterialEmission

makeMaterialVar :: Storable a
                => (GLenum -> GLenum -> Ptr a -> IO ())
                -> (GLenum -> GLenum -> Ptr a -> IO ())
                -> MaterialParameter -> Face -> StateVar a
makeMaterialVar getter setter materialParameter face =
   makeStateVar (alloca $ \buf -> do getter f mp buf ; peek buf)
                (\val -> with val $ setter f mp)
   where mp = marshalMaterialParameter materialParameter
         f  = marshalFace face

glGetMaterialfvc :: GLenum -> GLenum -> Ptr (Color4 GLfloat) -> IO ()
glGetMaterialfvc face pname ptr = glGetMaterialfv face pname (castPtr ptr)

glMaterialfvc :: GLenum -> GLenum -> Ptr (Color4 GLfloat) -> IO ()
glMaterialfvc face pname ptr = glMaterialfv face pname (castPtr ptr)

--------------------------------------------------------------------------------

materialShininess :: Face -> StateVar GLfloat
materialShininess =
   makeMaterialVar glGetMaterialfvf glMaterialff MaterialShininess

glGetMaterialfvf :: GLenum -> GLenum -> Ptr GLfloat -> IO ()
glGetMaterialfvf face pname ptr = glGetMaterialfv face pname (castPtr ptr)

glMaterialff :: GLenum -> GLenum -> Ptr GLfloat -> IO ()
glMaterialff face pname ptr = glMaterialfv face pname (castPtr ptr)

maxShininess :: GettableStateVar GLfloat
maxShininess = makeGettableStateVar $ getFloat1 id GetMaxShininess

--------------------------------------------------------------------------------

-- Alas, (Index1 GLint, Index1 GLint, Index1 GLint) is not an instance of
-- Storable...

materialColorIndexes ::
   Face -> StateVar (Index1 GLint, Index1 GLint, Index1 GLint)
materialColorIndexes face =
   makeStateVar (getMaterialColorIndexes face) (setMaterialColorIndexes face)

getMaterialColorIndexes :: Face -> IO (Index1 GLint, Index1 GLint, Index1 GLint)
getMaterialColorIndexes face =
   allocaArray 3 $ \buf -> do
      glGetMaterialiv (marshalFace face)
                      (marshalMaterialParameter MaterialColorIndexes)
                      buf
      peek3 (\a d s -> (Index1 a, Index1 d, Index1 s)) buf

setMaterialColorIndexes ::
   Face -> (Index1 GLint, Index1 GLint, Index1 GLint) -> IO ()
setMaterialColorIndexes face (Index1 a, Index1 d, Index1 s) =
   withArray [a, d, s] $
      glMaterialiv (marshalFace face)
                   (marshalMaterialParameter MaterialColorIndexes)

--------------------------------------------------------------------------------

data LightParameter =
     Ambient'
   | Diffuse'
   | Specular'
   | Position
   | SpotDirection
   | SpotExponent
   | SpotCutoff
   | ConstantAttenuation
   | LinearAttenuation
   | QuadraticAttenuation

marshalLightParameter :: LightParameter -> GLenum
marshalLightParameter x = case x of
   Ambient' -> 0x1200
   Diffuse' -> 0x1201
   Specular' -> 0x1202
   Position -> 0x1203
   SpotDirection -> 0x1204
   SpotExponent -> 0x1205
   SpotCutoff -> 0x1206
   ConstantAttenuation -> 0x1207
   LinearAttenuation -> 0x1208
   QuadraticAttenuation -> 0x1209

--------------------------------------------------------------------------------

ambient :: Light -> StateVar (Color4 GLfloat)
ambient = makeLightVar glGetLightfvc glLightfvc Ambient' black

black :: Color4 GLfloat
black = Color4 0 0 0 0

diffuse :: Light -> StateVar (Color4 GLfloat)
diffuse = makeLightVar glGetLightfvc glLightfvc Diffuse' black

specular :: Light -> StateVar (Color4 GLfloat)
specular = makeLightVar glGetLightfvc glLightfvc Specular' black

makeLightVar :: Storable a
             => (GLenum -> GLenum -> Ptr a -> IO ())
             -> (GLenum -> GLenum -> Ptr a -> IO ())
             -> LightParameter -> a -> Light -> StateVar a
makeLightVar getter setter lightParameter defaultValue theLight =
   makeStateVar (maybe (return defaultValue) getLightVar ml)
                (\val -> maybe recordInvalidEnum (setLightVar val) ml)
   where lp          = marshalLightParameter lightParameter
         ml          = marshalLight theLight
         getLightVar = \l -> alloca $ \buf -> do getter l lp buf ; peek buf
         setLightVar = \val l -> with val $ setter l lp

glGetLightfvc :: GLenum -> GLenum -> Ptr (Color4 GLfloat) -> IO ()
glGetLightfvc l pname ptr = glGetLightfv l pname (castPtr ptr)

glLightfvc :: GLenum -> GLenum -> Ptr (Color4 GLfloat) -> IO ()
glLightfvc l pname ptr = glLightfv l pname (castPtr ptr)

--------------------------------------------------------------------------------

position :: Light -> StateVar (Vertex4 GLfloat)
position = makeLightVar glGetLightfvv glLightfvv Position (Vertex4 0 0 0 0)

glLightfvv :: GLenum -> GLenum -> Ptr (Vertex4 GLfloat) -> IO ()
glLightfvv l pname ptr = glLightfv l pname (castPtr ptr)

glGetLightfvv :: GLenum -> GLenum -> Ptr (Vertex4 GLfloat) -> IO ()
glGetLightfvv l pname ptr = glGetLightfv l pname (castPtr ptr)

--------------------------------------------------------------------------------

spotDirection :: Light -> StateVar (Normal3 GLfloat)
spotDirection =
   makeLightVar glGetLightfvn glLightfvn SpotDirection (Normal3 0 0 0)

glLightfvn :: GLenum -> GLenum -> Ptr (Normal3 GLfloat) -> IO ()
glLightfvn l pname ptr = glLightfv l pname (castPtr ptr)

glGetLightfvn :: GLenum -> GLenum -> Ptr (Normal3 GLfloat) -> IO ()
glGetLightfvn l pname ptr = glGetLightfv l pname (castPtr ptr)

--------------------------------------------------------------------------------

spotExponent :: Light -> StateVar GLfloat
spotExponent = makeLightVar glGetLightfv glLightfv SpotExponent 0

maxSpotExponent :: GettableStateVar GLfloat
maxSpotExponent = makeGettableStateVar $ getFloat1 id GetMaxSpotExponent

--------------------------------------------------------------------------------

spotCutoff :: Light -> StateVar GLfloat
spotCutoff = makeLightVar glGetLightfv glLightfv SpotCutoff 0

--------------------------------------------------------------------------------

attenuation :: Light -> StateVar (GLfloat, GLfloat, GLfloat)
attenuation theLight =
   makeStateVar
      (liftM3 (,,) (get (constantAttenuation  theLight))
                   (get (linearAttenuation    theLight))
                   (get (quadraticAttenuation theLight)))
      (\(constant, linear, quadratic) -> do
         constantAttenuation  theLight $= constant
         linearAttenuation    theLight $= linear
         quadraticAttenuation theLight $= quadratic)

constantAttenuation :: Light -> StateVar GLfloat
constantAttenuation = makeLightVar glGetLightfv glLightfv ConstantAttenuation 0

linearAttenuation :: Light -> StateVar GLfloat
linearAttenuation = makeLightVar glGetLightfv glLightfv LinearAttenuation 0

quadraticAttenuation :: Light -> StateVar GLfloat
quadraticAttenuation =
   makeLightVar glGetLightfv glLightfv QuadraticAttenuation 0

--------------------------------------------------------------------------------

data LightModelParameter =
     LightModelAmbient
   | LightModelLocalViewer
   | LightModelTwoSide
   | LightModelColorControl

marshalLightModelParameter :: LightModelParameter -> GLenum
marshalLightModelParameter x = case x of
   LightModelAmbient -> 0xb53
   LightModelLocalViewer -> 0xb51
   LightModelTwoSide -> 0xb52
   LightModelColorControl -> 0x81f8

--------------------------------------------------------------------------------

lightModelAmbient :: StateVar (Color4 GLfloat)
lightModelAmbient =
   makeStateVar
      (getFloat4 Color4 GetLightModelAmbient)
      (\c -> with c $
                glLightModelfv (marshalLightModelParameter LightModelAmbient) . castPtr)

--------------------------------------------------------------------------------

lightModelLocalViewer :: StateVar Capability
lightModelLocalViewer =
   makeLightModelCapVar GetLightModelLocalViewer LightModelLocalViewer

makeLightModelCapVar :: GetPName -> LightModelParameter -> StateVar Capability
makeLightModelCapVar pname lightModelParameter =
   makeStateVar
      (getBoolean1 unmarshalCapability pname)
      (glLightModeli (marshalLightModelParameter lightModelParameter) .
                     fromIntegral . marshalCapability)

--------------------------------------------------------------------------------

lightModelTwoSide :: StateVar Capability
lightModelTwoSide = makeLightModelCapVar GetLightModelTwoSide LightModelTwoSide

vertexProgramTwoSide :: StateVar Capability
vertexProgramTwoSide = makeCapability CapVertexProgramTwoSide

--------------------------------------------------------------------------------

data LightModelColorControl =
     SingleColor
   | SeparateSpecularColor
   deriving ( Eq, Ord, Show )

marshalLightModelColorControl :: LightModelColorControl -> GLenum
marshalLightModelColorControl x = case x of
   SingleColor -> 0x81f9
   SeparateSpecularColor -> 0x81fa

unmarshalLightModelColorControl :: GLenum -> LightModelColorControl
unmarshalLightModelColorControl x
   | x == 0x81f9 = SingleColor
   | x == 0x81fa = SeparateSpecularColor
   | otherwise = error ("unmarshalLightModelColorControl: illegal value " ++ show x)

--------------------------------------------------------------------------------

lightModelColorControl :: StateVar LightModelColorControl
lightModelColorControl =
   makeStateVar
      (getEnum1 unmarshalLightModelColorControl GetLightModelColorControl)
      (glLightModeli (marshalLightModelParameter LightModelColorControl) .
                     fromIntegral . marshalLightModelColorControl)

--------------------------------------------------------------------------------

data ColorMaterialParameter =
     Ambient
   | Diffuse
   | Specular
   | Emission
   | AmbientAndDiffuse
   deriving ( Eq, Ord, Show )

marshalColorMaterialParameter :: ColorMaterialParameter -> GLenum
marshalColorMaterialParameter x = case x of
   Ambient -> 0x1200
   Diffuse -> 0x1201
   Specular -> 0x1202
   Emission -> 0x1600
   AmbientAndDiffuse -> 0x1602

unmarshalColorMaterialParameter :: GLenum -> ColorMaterialParameter
unmarshalColorMaterialParameter x
   | x == 0x1200 = Ambient
   | x == 0x1201 = Diffuse
   | x == 0x1202 = Specular
   | x == 0x1600 = Emission
   | x == 0x1602 = AmbientAndDiffuse
   | otherwise = error ("unmarshalColorMaterialParameter: illegal value " ++ show x)

--------------------------------------------------------------------------------

colorMaterial :: StateVar (Maybe (Face, ColorMaterialParameter))
colorMaterial =
   makeStateVarMaybe
      (return CapColorMaterial)
      (liftM2
         (,)
         (getEnum1 unmarshalFace GetColorMaterialFace)
         (getEnum1 unmarshalColorMaterialParameter GetColorMaterialParameter))
      (\(face, param) -> glColorMaterial (marshalFace face)
                                         (marshalColorMaterialParameter param))

--------------------------------------------------------------------------------

data ShadingModel =
     Flat
   | Smooth
   deriving ( Eq, Ord, Show )

marshalShadingModel :: ShadingModel -> GLenum
marshalShadingModel x = case x of
   Flat -> 0x1d00
   Smooth -> 0x1d01

unmarshalShadingModel :: GLenum -> ShadingModel
unmarshalShadingModel x
   | x == 0x1d00 = Flat
   | x == 0x1d01 = Smooth
   | otherwise = error ("unmarshalShadingModel: illegal value " ++ show x)

--------------------------------------------------------------------------------

shadeModel :: StateVar ShadingModel
shadeModel =
   makeStateVar
      (getEnum1 unmarshalShadingModel GetShadeModel)
      (glShadeModel . marshalShadingModel)
