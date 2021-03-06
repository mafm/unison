package org.unisonweb.util

abstract class Block[A] {
  /** Create a copy of `len` elements of this `Block`, starting from index `from`. */
  def copy(from: Int, len: Int): Block[A]

  /** Set the `i` index of this `Block`, extending the backing storage if needed. */
  def :+(i: Int, e: A): Block[A]

  /** Copy `len` elements of es to the `i` index of this `Block`. */
  def :++(i: Int, es: Array[A], len: Int): Block[A]

  /** Copy the first `len` elements of this `Block` to the `destIndex` position of `dest`. */
  def copyTo(destIndex: Int, dest: Block[A], len: Int): Block[A]

  /** The element at the provided index. */
  def apply(i: Int): A

  /** Create an empty version of this same `Block`, using the same kind of backing storage. */
  def empty: Block[A]

  /** Convert the first `size` elements of this `Block` to an array. */
  def toArray(size: Int): Array[A]
}

object Block {

  def viewArray[A](arr: Array[A])(implicit newArray: NewArray[A]): Block[A] = new Block[A] {
    def copy(from: Int, len: Int) = {
      val arr2 = newArray(len)
      Array.copy(arr, from, arr2, 0, arr2.length)
      fromArray(arr2)
    }
    def copyTo(i: Int, b2: Block[A], len: Int) = b2 :++ (i, arr, len)

    def apply(i: Int) = arr(i)

    def :++(i: Int, src: Array[A], len: Int) = {
      val arr2 = if (i + len >= arr.length) {
        val arr2 = newArray((arr.length * 2) max (len + i))
        Array.copy(arr, 0, arr2, 0, i)
        arr2
      } else arr
      Array.copy(src, 0, arr2, i, len)
      if (arr2 eq arr) this else viewArray(arr2)
    }

    def :+(i: Int, a: A) = {
      val arr2 =
        if (i >= arr.length) {
          val arr2 = newArray((arr.length * 2) max (i + 1))
          Array.copy(arr, 0, arr2, 0, arr.length)
          arr2
        }
        else arr
      arr2(i) = a
      if (arr2 eq arr) this else viewArray(arr2)
    }

    def empty = fromArray(newArray(16))
    def toArray(size: Int) = { val r = newArray(size); Array.copy(arr, 0, r, 0, r.length); r }
  }

  def fromArray[A](arr: Array[A])(implicit newArray: NewArray[A]): Block[A] =
    viewArray(arr.clone)

  def empty[A](implicit newArray: NewArray[A]): Block[A] =
    viewArray(newArray(16))

  abstract class NewArray[A] { def apply(size: Int): Array[A] }

  object NewArray extends LowPriorityNewArrays {
    implicit val Byte = new NewArray[Byte] { def apply(size: Int) = new Array[Byte](size) }
    implicit val Double = new NewArray[Double] { def apply(size: Int) = new Array[Double](size) }
    implicit val Long = new NewArray[Long] { def apply(size: Int) = new Array[Long](size) }
    implicit val Int = new NewArray[Int] { def apply(size: Int) = new Array[Int](size) }
  }

  trait LowPriorityNewArrays {
    val AnyRef = new NewArray[AnyRef] { def apply(size: Int) = new Array[AnyRef](size) }
    implicit def Polymorphic[A]: NewArray[A] = AnyRef.asInstanceOf[NewArray[A]]
  }
}
