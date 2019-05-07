using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class CameraRotate : MonoBehaviour
{
    private Transform camTrans;
    private Vector3 camAng;
    // Start is called before the first frame update
    void Start()
    {
        camTrans = this.transform;

        //Vector3 startPos = transform.position;

        //startPos.y += camHeight;

        //camTrans.position = startPos;

        //camTrans.rotation = transform.rotation;

        camAng = camTrans.eulerAngles;
        Application.targetFrameRate = 60;
    }

    // Update is called once per frame
    void Update()
    {
        if (camAng.x <= 60 && camAng.x >= -60)
        {
            camAng.x -=  Input.GetAxis("Vertical");
        }
        if (camAng.x > 60)
        {
            Vector3 cameuler = camAng;
            cameuler.x = 60;
            camAng = cameuler;
        }
        if (camAng.x < -60)
        {
            Vector3 cameuler = camAng;
            cameuler.x = -60;
            camAng = cameuler;
        }

            camAng.y +=  Input.GetAxis("Horizontal");

            camTrans.eulerAngles = camAng;
     
        
    }
}
