# Example code to show how to use IoT Core Device Shadows with AppSync

## Deploy

* ```terraform init```
* ```terraform apply```

This creates an AppSync API and an IoT Thing. The API reads and writes the ```test``` shadow of the Thing.

## Usage

Get the current value from a device shadow:

```graphql
query MyQuery {
  current
}
```

Result:

```json
{
  "data": {
    "current": 0
  }
}
```

Increase the value (and create the shadow in the first call):

```graphql
mutation MyMutation {
  increase
}
```

```json
{
  "data": {
    "increase": 1
  }
}
```

![image](https://user-images.githubusercontent.com/82075/181208336-7e1514d2-97a7-43da-a0a3-ccd736c81d8e.png)

## Cleanup

* ```terraform destroy```
