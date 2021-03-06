{-|
Module      : Data.Matrix
Description : Typesafe matrix operations.
Copyright   : (c) Anatoly Yakovenko, 2015-2016
License     : MIT
Maintainer  : aeyakovenko@gmail.com
Stability   : experimental
Portability : POSIX

This module implements some matrix operations using the Repa package that track the symbolic shape of the matrix.
-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE EmptyDataDecls #-}
module Data.Matrix( Matrix(..)
                  , MatrixOps(..)
                  , R.U
                  , R.D
                  , B
                  , I
                  , H
                  ) where

import Prelude as P
import Data.Binary(Binary,put,get)
import qualified Data.Array.Repa as R
import qualified Data.Array.Repa.Algorithms.Matrix as R
import qualified Data.Array.Repa.Unsafe as Unsafe
import qualified Data.Array.Repa.Algorithms.Randomish as R
import qualified Data.Vector.Unboxed as V
import Control.DeepSeq(NFData, rnf)
import Data.Array.Repa(Array
                      ,U
                      ,D
                      ,DIM2
                      ,Any(Any)
                      ,Z(Z)
                      ,(:.)((:.))
                      ,All(All)
                      )
-- | num hidden nodes
data H 

-- | num input nodes
data I 

-- | num inputs in batch
data B 

-- | wraps the Repa Array types so we can typecheck the results of
-- | the matrix operations
data Matrix d a b = R.Source d Double => Matrix (Array d DIM2 Double)
instance Show (Matrix U a b) where
   show m = show $ toList m

instance NFData (Matrix U a b) where
   rnf (Matrix ar) = ar `R.deepSeqArray` ()

-- |Class implementing the typesafe Matrix apis
class MatrixOps a b where
   mmult :: Monad m => (Matrix U a b) -> (Matrix U b c) -> m (Matrix U a c)
   mmult (Matrix ab) (Matrix ba) = Matrix <$> (ab `mmultP` ba)

   mmultT :: Monad m => (Matrix U a b) -> (Matrix U c b) -> m (Matrix U a c)
   mmultT (Matrix ab) (Matrix ab') = Matrix <$> (ab `mmultTP` ab')

   d2u :: Monad m => Matrix D a b -> m (Matrix U a b)
   d2u (Matrix ar) = Matrix <$> (R.computeP ar)

   (*^) :: Matrix c a b -> Matrix d a b -> (Matrix D a b)
   (Matrix ab) *^ (Matrix ab') = Matrix (ab R.*^ ab')
   {-# INLINE (*^) #-}

   (+^) :: Matrix c a b -> Matrix d a b -> (Matrix D a b)
   (Matrix ab) +^ (Matrix ab') = Matrix (ab R.+^ ab')
   {-# INLINE (+^) #-}

   (-^) :: Matrix c a b -> Matrix d a b -> (Matrix D a b)
   (Matrix ab) -^ (Matrix ab') = Matrix (ab R.-^ ab')
   {-# INLINE (-^) #-}

   map :: (Double -> Double) -> Matrix c a b -> (Matrix D a b)
   map f (Matrix ar) = Matrix (R.map f ar)
   {-# INLINE map #-}

   cast1 :: Matrix c a b -> Matrix c d b
   cast1 (Matrix ar) = Matrix ar
   {-# INLINE cast1 #-}

   cast2 :: Matrix c a b -> Matrix c a d
   cast2 (Matrix ar) = Matrix ar
   {-# INLINE cast2 #-}

   transpose :: Monad m => Matrix U a b -> m (Matrix U b a)
   transpose (Matrix ar) = Matrix <$> (R.transpose2P ar)
   {-# INLINE transpose #-}

   sum :: Monad m =>  Matrix c a b -> m Double
   sum (Matrix ar) = R.sumAllP ar
   {-# INLINE sum #-}

   mse :: Monad m => Matrix c a b -> m Double
   mse errm = do
      terr <- Data.Matrix.sum $ Data.Matrix.map (\ x -> x ** 2) errm
      return (terr/(1 + (fromIntegral $ elems errm)))
   {-# INLINE mse #-}

   elems :: Matrix c a b -> Int
   elems m = (row m) * (col m)
   {-# INLINE elems #-}

   row :: Matrix c a b -> Int
   row (Matrix ar) = (R.row (R.extent ar))
   {-# INLINE row #-}

   col :: Matrix c a b -> Int
   col (Matrix ar) = (R.col (R.extent ar))
   {-# INLINE col #-}

   shape :: Matrix c a b -> (Int,Int)
   shape m = (row m, col m)
   {-# INLINE shape #-}

   randomish :: (Int,Int) -> (Double,Double) -> Int -> Matrix U a b
   randomish (r,c) (minv,maxv) seed = Matrix $ R.randomishDoubleArray (Z :. r :. c) minv maxv seed
   {-# INLINE randomish #-}

   splitRows :: Int -> Matrix c a b -> [Matrix D a b]
   splitRows nr m1 = P.map (extractRows m1) chunks
      where chunks = P.map maxn $ zip rixs (repeat nr)
            maxn (rix,num) 
               | rix + num > (row m1) = (rix, (row m1) - rix)
               | otherwise = (rix, num)
            rixs = [0,nr..(row m1)-1]
            extractRows :: Matrix c a b -> (Int,Int) -> Matrix D a b 
            extractRows m2@(Matrix ar) (rix,num) = Matrix $ R.extract
                                                   (Z :. rix :. 0)
                                                   (Z :. num :. (col m2))
                                                   ar
   {-# INLINE splitRows #-}
         

   zipWith :: (Double -> Double -> Double) -> Matrix c a b -> Matrix c a b -> (Matrix D a b)
   zipWith f (Matrix aa) (Matrix bb) = Matrix (R.zipWith f aa bb)
   {-# INLINE zipWith #-}

   fromList :: (Int,Int) -> [Double] -> Matrix U a b
   fromList (r,c) lst = Matrix $ R.fromListUnboxed (Z:.r:.c) lst
   {-# INLINE fromList #-}

   traverse :: (Double -> Int -> Int -> Double) -> Matrix c a b -> Matrix D a b
   traverse ff (Matrix ar) = Matrix $ R.traverse ar id func
         where func gv sh@(Z :. rr :. cc) = ff (gv sh) rr cc
   {-# INLINE traverse #-}

   toList :: Matrix U a b -> [Double]
   toList (Matrix ab) = R.toList ab
   {-# INLINE toList #-}

   fold :: Monad m => (Double -> Double -> Double) -> Double -> Matrix U a b -> m Double
   fold f z (Matrix ab) = R.foldAllP f z ab
   {-# INLINE fold #-}

   toUnboxed :: Matrix U a b -> V.Vector Double
   toUnboxed (Matrix ar) = R.toUnboxed ar
   {-# INLINE toUnboxed #-}

instance MatrixOps a b where

instance Binary (Matrix U a b) where
   put m = put (shape m, toList m)
   get = (uncurry fromList) <$> get

{-|
 - matrix multiply
 - A x (transpose B)
 - based on mmultP from repa-algorithms-3.3.1.2
 -}
mmultTP  :: Monad m
        => Array U DIM2 Double
        -> Array U DIM2 Double
        -> m (Array U DIM2 Double)
mmultTP arr trr
 = [arr, trr] `R.deepSeqArrays`
   do
        let (Z :. h1  :. _) = R.extent arr
        let (Z :. w2  :. _) = R.extent trr
        R.computeP
         $ R.fromFunction (Z :. h1 :. w2)
         $ \ix   -> R.sumAllS
                  $ R.zipWith (*)
                        (Unsafe.unsafeSlice arr (Any :. (R.row ix) :. All))
                        (Unsafe.unsafeSlice trr (Any :. (R.col ix) :. All))
{-# NOINLINE mmultTP #-}

{-|
 - regular matrix multiply
 - A x B
 - based on mmultP from repa-algorithms-3.3.1.2
 - moved the deepseq to evaluate the transpose(B) instead of B
 -}
mmultP  :: Monad m
        => Array U DIM2 Double
        -> Array U DIM2 Double
        -> m (Array U DIM2 Double)
mmultP arr brr
 = do   trr <- R.transpose2P brr
        mmultTP arr trr
