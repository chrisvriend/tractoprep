# ENIGMA OCD 

Below is an outline of the steps for the ENIGMA OCD structural connectome project.

### Settings
in the spec.json file keep these parameters at their default setting and specify the name of your site/sample:
"eddy_method": "default",
"nstreamlines": "20M",
"sitename": "OCD_site1"


### Finished processing, now what?!
After preprocessing, qc-ing an running tractography to produce the structural connectome
it is high time to upload the data. you can use [dwi-send](running.md#dwi-send) to automatically organize the 
relevant data in a tar file saved in /derivatives. 


```{important}
While the tractoprep pipeline allows the user to rely on existing FreeSurfer output,
we kindly ask you to run FreeSurfer (v8.2.0) using this pipeline in preparation of future projects.
```


### Clinical Covariates File
- Download the [clinical covariates file](https://surfdrive.surf.nl/s/2FETNYWDKsfswrn)
- add the relevant demographic and clinical details for your participants with subject IDs starting with `sub-`
- save the covariates file with the name of your `sample` in the filename.

### Up, Up and Away

Upload the tar.bz2 file with the imaging measures and the clinical covariates file 
to this [SurfDrive Dropbox](https://surfdrive.surf.nl/s/9LycMLdAWRR7mMm)



### Questions?
contact: c|dot| vriend ~ at ~ amsterdamumc|dot| nl